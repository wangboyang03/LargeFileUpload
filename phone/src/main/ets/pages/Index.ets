import { FileSelectedResponse } from '../models'
import { FileUploadUtil } from '../utils';
import { PromptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  // @State message: string = 'Hello World';
  @State selectedFile: FileSelectedResponse = {
    fileName: "",
    filePath: "",
    fileSize: 0,
    fileHash: "",
    totalChunks: 0,
  } as FileSelectedResponse // 选择文件对象
  @State uploadProgress:number = 0 // 当前进度
  @State isUploading: boolean = false // 是否正在上传
  promptAction: PromptAction = this.getUIContext().getPromptAction()

  @State uploadSpeed: number = 0 // 用于前台显示上传速度
  @State uploadedChunks: number = 0 // 已上传分片数
  @State isResuming: boolean = false // 环境是否为断点续传
  @State logMessages: string[] = [] // 日志消息
  Scroller: Scroller = new Scroller() // 滚动容器控制器

  /**
   * 添加日志消息
   * @param message 日志内容
   */
  addLog(message: string): void {
    const currentTime = new Date()
    const hours = String(currentTime.getHours()).padStart(2, '0')
    const minutes = String(currentTime.getMinutes()).padStart(2, '0')
    const seconds = String(currentTime.getSeconds()).padStart(2, '0')
    const timeString = `${hours}:${minutes}:${seconds}`
    const logEntry = `${timeString}: ${message}`
    this.logMessages.push(logEntry)
  }

  build() {
    Column() {
      Button('选择文件')
        .onClick(async () => {
          this.logMessages = [] // 每次选择文件先清空上一次日志
          this.addLog('开始选择文件...')
          const file = await FileUploadUtil.getInstance().selectFile()
          if (!!file) {
            this.selectedFile = file
            this.addLog(`已选择文件: ${file.fileName} (${(file.fileSize / 1024 / 1024).toFixed(2)} MB)`)
            this.addLog(`文件哈希值: ${file.fileHash}`)
            if (!this.selectedFile.fileHash) {
              this.addLog('暂时无法上传沙箱外的文件，本次选择作废请重新选择')
              return
            }
            this.addLog(`文件将被分为 ${file.totalChunks} 个分片`)
            
            // 检查是否有已上传的分片
            const cache = FileUploadUtil.getInstance().getUploadCache()
            if (cache && cache.uploadedChunks.size > 0) {
              this.isResuming = true
              this.uploadedChunks = cache.uploadedChunks.size
              this.addLog(`检测到已上传分片: ${cache.uploadedChunks.size} / ${file.totalChunks}, 当前环境是断点续传`)
            } else {
              this.isResuming = false
              this.addLog('这是新文件，需要上传所有分片')
            }
          } else {
            this.addLog('用户取消了文件选择')
          }
        })
      Column({space: 5}) {
        Text(this.selectedFile.fileName ? `文件名: ${this.selectedFile.fileName}` : '请先选择文件')
          .fontSize(12)
          .margin({ top: 4 })
        Text("文件大小: "+`${(this.selectedFile.fileSize / 1024 / 1024).toFixed(2)} MB`)
          .fontSize(12)
        Text(this.selectedFile.fileHash ? `文件哈希值: ${this.selectedFile.fileHash}` : '当前无法获取哈希值')
          .fontSize(12)
        if (this.isResuming && this.uploadedChunks > 0) {
          Text(`断点续传环境,已上传 ${this.uploadedChunks}/${this.selectedFile.totalChunks} 个分片`)
            .fontSize(12)
            .fontColor($r('sys.color.multi_color_10'))
        }
        Text(`上传进度: ${this.uploadProgress}%`)
          .fontSize(12)
          .margin({ top: 4 })
        if (this.isUploading && this.uploadSpeed > 0) {
          Text(`上传速度: ${this.uploadSpeed.toFixed(2)} MB/s`)
            .fontSize(12)
            .fontColor('#4CAF50')
        }
        Button(this.isUploading ? '上传中' : '开始上传')
          .enabled(!!this.selectedFile.fileHash)
          .onClick(async () => {
            this.isUploading = true
            try {
              const result = await FileUploadUtil.getInstance().upload(
                this.selectedFile.filePath,
                this.selectedFile.fileHash,
                this.selectedFile.fileName,
                (progress) => {
                  this.uploadProgress = progress.progress
                  this.uploadSpeed = progress.speed
                  this.uploadedChunks = progress.uploadedChunks
                },
                (logMsg: string) => this.addLog(logMsg) // 日志回调
              )
              if (result?.success) {
                this.addLog(`文件上传成功!`)
                this.addLog(`文件名: ${result.data.fileName}`)
                this.addLog(`保存路径: ${result.data.filePath}`)
              } else {
                this.addLog('上传失败: 服务器返回失败')
              }
            } catch (error) {
              this.addLog(`上传异常: ${JSON.stringify(error)}`)
            } finally {
              this.isUploading = false
              this.isResuming = false
            }
          })
      }
      
      // 日志显示区域
      if (this.logMessages.length > 0) {
        Column() {
          Text('上传日志')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 10, bottom: 5 })
          Scroll(this.Scroller) {
            Column({ space: 2 }) {
              ForEach(this.logMessages, (logItem: string) => {
                Text(logItem)
                  .fontSize(12)
                  .fontFamily('monospace') // 设置字体为等宽字体
                  .width('100%')
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              })
            }
            .width('100%')
          }
          .width('100%')
          .height(300)
          .backgroundColor('#FAFAFA')
          .padding(10)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off) // 关闭滚动条
          .onDidScroll(() => this.Scroller.scrollEdge(Edge.Bottom)) // 自动滚动到底部
        }
        .width('100%')
      }
    }
    .height('100%')
    .width('100%')
  }
}