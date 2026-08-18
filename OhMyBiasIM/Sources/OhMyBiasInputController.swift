@@
     func engineDidCommit(_ text: String) {
         guard let client = engineClient else { return }
         let range = client.markedRange()
         let output = text.replacingOccurrences(of: "\\n", with: "\n")
         if output.count > range.length && range.length > 0 {
             client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                  replacementRange: range)
             client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
         } else {
             client.insertText(output, replacementRange: range)
         }
+        // 播放按鍵音效（commit）
+        DispatchQueue.global(qos: .userInitiated).async {
+            SoundManager.shared.play("key")
+        }
     }
@@
     func engineDidDeleteBack() {
         guard let client = engineClient else { return }
         let sel = client.selectedRange()
         if sel.location != NSNotFound && sel.location > 0 {
             client.insertText("", replacementRange: NSRange(location: sel.location - 1, length: 1))
         }
+        // 播放刪除音
+        DispatchQueue.global(qos: .userInitiated).async {
+            SoundManager.shared.play("delete")
+        }
     }
