import { Log } from '@abner/log'

// 初始化
Log.init({
  tag: "大文件上传",
  domain: 0x0101,
  close: false,
  isHilog: true,
  showLogLocation: true,
  logSize: 1024
})


export { Log as Logger }