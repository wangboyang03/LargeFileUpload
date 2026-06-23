/**
 * 接口公共响应体
 */
export interface ResponseBasic<T> {
  success: boolean
  message: string
  data: T
}

// 选择文件信息 给前台显示
export interface FileSelectedResponse {
  fileName: string,
  fileSize: number,
  fileHash: string,
  filePath: string,
  totalChunks: number
}

/**
 * 文件上传接口
 */
export interface UploadCache {
  filePath: string
  fileName: string
  fileSize: number
  fileHash: string
  uploadedChunks: Set<number>
  totalChunks: number
}

/**
 * 进度回调
 */
interface UploadProgress {
  progress: number
  speed: number
  uploadedChunks: number
  totalChunks: number
  currentChunk: number
}

export type UploadProgressCallback = (info: UploadProgress) => void

/**
 * 日志回调类型
 */
export type LogCallback = (message: string) => void

export interface ChunksQueryRequest {
  fileHash: string
}

/**
 * 用于查询已上传的分片
 */
export interface ChunksQueryResponse {
  fileHash: string
  uploadedChunks: number[]
}

/**
 * 单品切片上传响应
 */
export interface ChunkUploadResponse {
  fileHash: string,
  chunkIndex: number,
  totalChunks: number
}

export interface uploadChunkTaskResponse {
  chunkIndex: number
  success: boolean
}

export interface FileMergeRequest {
  fileHash: string
  fileName: string
  totalChunks: number
}

export interface MergeResult {
  fileName: string
  filePath: string
}