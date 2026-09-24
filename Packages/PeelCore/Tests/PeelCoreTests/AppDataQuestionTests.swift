@testable import PeelCore
import Testing

struct AppDataQuestionTests {
    @Test func aScanWaitsOnMacOSOnlyWhileItsQuestionIsInFrontAndFullDiskAccessIsMissing() {
        #expect(AppDataQuestion.isAsked(frontmost: "com.apple.UserNotificationCenter", hasFullDiskAccess: false))
        #expect(!AppDataQuestion.isAsked(frontmost: "com.apple.UserNotificationCenter", hasFullDiskAccess: true))
        #expect(!AppDataQuestion.isAsked(frontmost: "com.apple.Safari", hasFullDiskAccess: false))
        #expect(!AppDataQuestion.isAsked(frontmost: nil, hasFullDiskAccess: false))
    }
}
