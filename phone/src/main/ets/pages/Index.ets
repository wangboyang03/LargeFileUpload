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

  build() {
    Column() {
      Button('选择文件')
        .onClick(async () => {
          const file = await FileUploadUtil.getInstance().selectFile()
          if (!!file) {
            this.selectedFile = file
          }
        })
      Column({space: 5}) {
        Text(this.selectedFile.fileName ? `文件名: ${this.selectedFile.fileName}` : '请先选择文件')
          .fontSize(12)
          .margin({ top: 4 })
        Text("文件大小: "+`${(this.selectedFile.fileSize / 1024 / 1024).toFixed(2)} MB`)
          .fontSize(12)
        Text(this.selectedFile.fileHash ? `文件哈希值: ${this.selectedFile.fileName}` : '当前无法获取哈希值')
          .fontSize(12)
        Text("切片数量: "+ this.selectedFile.totalChunks)
          .fontSize(12)
        Text(`上传进度: ${this.uploadProgress}%`)
          .fontSize(12)
          .margin({ top: 4 })
        Button(this.isUploading ? '上传中' : '开始上传')
          .enabled(!!this.selectedFile && !this.isUploading)
          .onClick(async () => {
            if (!this.selectedFile) {
              return this.promptAction.openToast({ message: '请先选择文件 '})
            }
            this.isUploading = true
            const result = await FileUploadUtil.getInstance().upload(
              this.selectedFile.filePath,
              this.selectedFile.fileHash,
              this.selectedFile.fileName,
              (progress) => this.uploadProgress = progress.progress
            )
            this.promptAction.showDialog({
              message: `文件上传成功, 文件${result?.data.fileName}已保存到路径: ${result?.data.filePath}`
            })
            this.isUploading = false
            return
          })
      }
    }
    .height('100%')
    .width('100%')
  }
}