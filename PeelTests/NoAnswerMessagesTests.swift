import Foundation
@testable import Peel
import Testing

struct NoAnswerMessagesTests {
    /// These show in place of a list, after the question that lists everything got no answer.
    @Test func eachSaysWhichQuestionGotNoAnswerAndWhatToDo() {
        #expect(PackageList.noAnswer.key.hasPrefix("Peel asked macOS which packages are installed and got no answer"))
        for message in [PackageList.noAnswer, ExtensionList.noAnswer] {
            #expect(message.key.hasSuffix("so it can’t list them. Rescan to try again."), "\(message.key)")
        }
    }
}
