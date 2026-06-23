import { fileIo, picker } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { buffer, taskpool } from '@kit.ArkTS'
import { rcp } from '@kit.RemoteCommunicationKit'
import { ChunksQueryRequest, ChunksQueryResponse, ChunkUploadResponse, FileMergeRequest, FileSelectedResponse, MergeResult, ResponseBasic, UploadCache, uploadChunkTaskResponse, UploadProgressCallback, LogCallback } from '../models'
import { Constants } from '../Constants'
import { Logger } from './Logger'
import { Configuration, promptAction } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

@Concurrent async function uploadChunkTask(filePath: string, fileName: string, chunkIndex: number, totalChunks: number, fileHash: string) {
  // 并发函数是全局函数 没有this上下文 也不能写闭包代码 调用外部方法
  try {
    const fileSize = fileIo.statSync(filePath).size
    const start = chunkIndex * Constants.DEFAULT_CHUNK_SIZE
    const end = Math.min(start + Constants.DEFAULT_CHUNK_SIZE, fileSize)
    // const buffer = new ArrayBuffer(end - start)
    // 文件处理
    const chunkSize = end - start
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
    const chunkBuffer = new ArrayBuffer(chunkSize)
    const readLen = fileIo.readSync(file.fd, chunkBuffer,
      {
        offset: start,
        length: chunkSize
      }
    )
    fileIo.closeSync(file)
    let _chunkBuffer = chunkBuffer
    if (readLen > 0 && readLen < chunkSize) {
      _chunkBuffer = chunkBuffer.slice(0, readLen)
    }
    const content: rcp.FileContent = { content: _chunkBuffer }

    const multiFormFieldValue: rcp.MultipartFormFieldValue = {
      remoteFileName: fileName,
      contentType: "multipart/form-data",
      contentOrPath: content
    }
    const simpleFrom = new rcp.MultipartForm({
      "chunk": multiFormFieldValue,
      "fileHash": fileHash,
      "chunkIndex": String(chunkIndex),
      "totalChunks": String(totalChunks),
      "fileName": fileName
    })

    const session = rcp.createSession()
    const request = new rcp.Request(Constants.BASE_URL + '/api/upload/chunk', 'POST', { 'Content-Type': 'multipart/form-data' }, simpleFrom)
    const result = await session.fetch(request)
    const resultData = result.toJSON() as ResponseBasic<ChunkUploadResponse>
    const success = resultData.success
    Logger.info(resultData)
    return {
      chunkIndex,
      success
    } as uploadChunkTaskResponse
  } catch (error) {
    Logger.error(error)
    return
  }
}

export class FileUploadUtil {
  private static sInstance: FileUploadUtil
  private session = rcp.createSession() // 远场通信会话实例
  private uploadCache = {} as UploadCache
  isUploading: boolean = false // 是否正在上传
  currentProgress: number = 0 // 当前进度

  private constructor() {} // 私有构造函数

  /**
   * 获取单例实例
   * @returns
   */
  static getInstance(): FileUploadUtil {
    if (!FileUploadUtil.sInstance) {
      FileUploadUtil.sInstance = new FileUploadUtil()
    }
    return FileUploadUtil.sInstance
  }

  /**
   * 远场通信公共请求方法
   * @param url 请求地址
   * @param method 请求方法
   * @param data 响应返回值
   * @param query Query参数
   * @param isUpload 是否是上传文件请求
   * @returns
   */
  async request<T>(url: string, method: rcp.HttpMethod, data?: Object, query?: object) {
    try {
      let finalUrl = url
      // 1.拼接Query参数
      if (query) {
        const queryString = Object.keys(query).filter(key => !!query[key]).map(key => `${key}=${query[key]}`).join('&')
        finalUrl += `?${queryString}`
      }
      // 2. headers类型
      const headers: rcp.RequestHeaders = { 'Content-Type': 'application/json' }
      // 3.统一处理请求
      const timeout: rcp.Configuration = {
        transfer: {
          timeout: {
            transferMs: Constants.TIME_OUT,
            connectMs: Constants.TIME_OUT,
            inactivityMs: Constants.TIME_OUT
          }
        }
      } // 超时时间
      const request = new rcp.Request(finalUrl, method, headers, data, {}, {}, timeout)
      const res = await this.session.fetch(request)
      return res.toJSON() as ResponseBasic<T>
    } catch (_error) {
      let error = _error as BusinessError
      Logger.error('出错了', JSON.stringify({ code: error.code, message: error.message }))
      if (error.code == 1007900028)
      promptAction.openToast({
        message: "连接超时,请检查网络连接。"
      })
      return
    }
  }

  /**
   * 获取上传缓存信息
   * @returns 上传缓存对象
   */
  getUploadCache() {
    if (this.uploadCache && this.uploadCache.fileHash) {
      return this.uploadCache
    }
    return null
  }

  /**
   * 上传文件
   * @param filePath 文件路径
   * @param fileHash 文件哈希值
   * @param fileName 文件名
   * @param onProgress Callback回调函数
   * @param onLog 日志回调函数
   * @returns 上传结果
   */
  async upload(filePath: string, fileHash: string, fileName: string, onProgress?: UploadProgressCallback, onLog?: LogCallback) {
    try {
      this.isUploading = true
      let lastUploadedBytes = 0 // 上次上传的字节数
      let markTime = Date.now() // 用于计算速度的时间标记
      const totalChunks = this.uploadCache.totalChunks
      // const alreadyUploaded = this.uploadCache.uploadedChunks.size // 已上传的分片数
      const log = (message: string) => {
        onLog?.(message)
      }

      // 进度回调 上传实时数据给前台页面
      const emitProgress = (currentChunk: number, completedCount: number) => {
        // Logger.info(`emitProgress completedCount=${completedCount}`)
        const currentTime = Date.now()
        const timeDiff = (currentTime - markTime) / 1000
        const uploadedChunks = this.uploadCache.uploadedChunks.size + completedCount
        const uploadedBytes = uploadedChunks * Constants.DEFAULT_CHUNK_SIZE
        const byteDiff = uploadedBytes - lastUploadedBytes

        const speed = timeDiff > 0 ? (byteDiff / 1024 / timeDiff) : 0 // 计算速度

        // 重置局部变量
        markTime = currentTime
        lastUploadedBytes = uploadedBytes

        const totalChunks = this.uploadCache.totalChunks
        const progress = Math.floor((uploadedChunks / totalChunks) * 100)
        this.currentProgress = progress

        onProgress?.({
          progress,
          speed,
          uploadedChunks,
          totalChunks,
          currentChunk
        })

        // Logger.info(`progress=${progress},
        //   uploadedChunks=${uploadedChunks}
        //   completedCount=${completedCount}
        //   cacheSize=${this.uploadCache.uploadedChunks.size}
        //   totalChunks=${totalChunks}
        // `)
      }
      emitProgress(-1, 0) // 需要将初始化进度、当前文件总切片数以及当前进度传给前台

      // 获取所有未上传的切片索引
      const chunksUpload: number[] = []
      for (let i = 0; i < totalChunks; i++) {
        if (!this.uploadCache.uploadedChunks.has(i)) {
          chunksUpload.push(i)
        }
      }

      if (chunksUpload.length > 0) {
        let completedCount = 0 // 已完成上传的切片数量
        let failedChunks: number[] = [] // 记录失败的分片
        for (let i = 0; i < chunksUpload.length; i++) {
          const chunkIndex = chunksUpload[i]
          
          // 最多重试3次
          let retryCount = 0
          const maxRetries = 3
          let success = false
          
          while (retryCount < maxRetries && !success) {
            try {
              if (retryCount > 0) {
                log(`分片${chunkIndex + 1}/${totalChunks}的第${retryCount + 1}次重试`)
              }
              const res = await taskpool.execute(uploadChunkTask, filePath, fileName, chunkIndex, totalChunks, fileHash) as uploadChunkTaskResponse
              if (res?.success) {
                success = true
                completedCount++
                // 更新缓存中的已上传分片
                this.uploadCache.uploadedChunks.add(chunkIndex)
                // 重新计算进度
                emitProgress(chunkIndex, completedCount)
                log(`分片${chunkIndex + 1}上传成功，当前进度：(${completedCount}/${chunksUpload.length})`)
              } else {
                retryCount++
                if (retryCount < maxRetries) {
                  log(`分片 ${chunkIndex + 1} 上传失败，重试次数(${retryCount}/${maxRetries})`)
                }
              }
            } catch (error) {
              retryCount++
              if (retryCount < maxRetries) {
                log(`分片 ${chunkIndex + 1} 上传异常，重试次数(${retryCount}/${maxRetries})`)
              }
            }
          }
          
          if (!success) {
            failedChunks.push(chunkIndex)
            log(`分片 ${chunkIndex + 1} 上传最终失败`)
          }
        }
      } else {
        log('所有分片已上传，直接合并文件')
      }

      const merge = await this.request<MergeResult>(`${Constants.BASE_URL}/api/upload/merge`, 'POST', {
        fileHash,
        fileName,
        totalChunks,
      } as FileMergeRequest)

      if (merge?.success) {
        this.currentProgress = 100
        emitProgress(totalChunks - 1, totalChunks)
        log('文件合并成功，上传完成!')
      }
      this.isUploading = false
      return merge
    } catch (error) {
      this.isUploading = false
      onLog?.(`上传失败: ${JSON.stringify(error)}`)
      return
    }
  }

  /**
   * 创建文件哈希值
   * @param filePath 文件路径
   * @returns 文件哈希值
   */
  private async createFileHash(filePath: string) {
    try {
      const md = cryptoFramework.createMd('MD5')
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const fileSize = fileIo.statSync(filePath).size
      let offset: number = 0
      while (offset < fileSize) {
        const size = Math.min(Constants.DEFAULT_CHUNK_SIZE, fileSize - offset)
        const buffer = new ArrayBuffer(size)
        const len = fileIo.readSync(file.fd, buffer, {
          offset: offset,
          length: size
        })
        if (len > 0) {
          const uint8Array = new Uint8Array(buffer.slice(0, len))
          const blob: cryptoFramework.DataBlob = { data: uint8Array }
          await md.update(blob)
        }
        offset += size
      }
      fileIo.closeSync(file)
      const mdOutput = await md.digest()
      return buffer.from(mdOutput.data).toString('hex')
    } catch (error) {
      Logger.error(error)
      return ""
    }
  }

  /**
   * 选择文件
   * @returns 文件信息
   */
  async selectFile() {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      const result = await documentPicker.select(options)
      if (result && result.length > 0) {
        const uri = result[0]
        const file = fileIo.openSync(uri)
        const fileSize = fileIo.statSync(file.fd).size
        const fileHash = await this.createFileHash(file.path)

        const totalChunks = Math.ceil(fileSize / Constants.DEFAULT_CHUNK_SIZE) // 计算总切片数
        const res = await this.request<ChunksQueryResponse>(`${Constants.BASE_URL}/api/upload/check`, 'GET', undefined, { fileHash } as ChunksQueryRequest)
        const uploadedChunks = new Set<number>(res?.data?.uploadedChunks ?? []) // 已上传的切片索引 后端返回
        const alreadyUploaded = uploadedChunks.size

        // 缓存文件信息
        this.uploadCache = {
          filePath: file.path,
          fileName: file.name,
          fileSize,
          fileHash,
          uploadedChunks,
          totalChunks
        }

        return {
          filePath:file.path,
          fileName: file.name,
          fileSize,
          fileHash,
          totalChunks,
        } as FileSelectedResponse
      }
      return
    } catch (error) {
      Logger.error(error)
      return
    }
  }
}