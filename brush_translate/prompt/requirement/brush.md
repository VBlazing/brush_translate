## 需求描述
优化 `copyFromPasteboardSelection` 方法

### 细节
1. 如果用户未选中文本，禁止将之前 pasteboard 中的内容赋值给 copied，直接返回空字符串
