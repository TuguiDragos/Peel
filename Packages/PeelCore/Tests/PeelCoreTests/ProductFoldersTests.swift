import Foundation
@testable import PeelCore
import Testing

struct ProductFoldersTests {
    @Test func readsTheFoldersAnIDEAndACodeEditorName() throws {
        let directory = try TemporaryDirectory()
        let ide = try directory.directory("Applications/Example IDE.app")
        try directory.file(
            "Applications/Example IDE.app/Contents/Resources/product-info.json",
            contents: Data(#"{"productVendor": "ExampleVendor", "dataDirectoryName": "ExampleIDE2025.2"}"#.utf8)
        )
        let editor = try directory.directory("Applications/Example Editor.app")
        try directory.file(
            "Applications/Example Editor.app/Contents/Resources/app/product.json",
            contents: Data(#"{"dataFolderName": ".example-editor", "sharedDataFolderName": ".example-editor-shared"}"#.utf8)
        )

        #expect(ProductFolders.of(appAt: ide) == [
            ProductFolder(
                path: "Library/Application Support/ExampleVendor/ExampleIDE2025.2", proof: nil,
                work: ["scratches", "consoles"]
            ),
            ProductFolder(path: "Library/Caches/ExampleVendor/ExampleIDE2025.2", proof: nil),
            ProductFolder(path: "Library/Logs/ExampleVendor/ExampleIDE2025.2", proof: nil),
        ])
        #expect(ProductFolders.of(appAt: editor) == [
            ProductFolder(path: ".example-editor", proof: "argv.json"),
            ProductFolder(path: ".example-editor-shared", proof: "sharedStorage"),
        ])
        #expect(ProductFolders.of(appAt: try directory.directory("Applications/Plain.app")).isEmpty)
    }

    @Test func namesTheFolderACodeEditorKeepsItsDataInAndTheWorkInside() {
        let data = ProductFolder(
            path: "Library/Application Support/Example Editor", proof: "User/globalStorage/storage.json",
            work: ["Backups", "User/History"]
        )

        let folders = ProductFolders.vsCodeFolders(in: ["nameShort": "Example Editor", "dataFolderName": ".example-editor"])

        #expect(folders == [ProductFolder(path: ".example-editor", proof: "argv.json"), data])
        #expect(ProductFolders.vsCodeFolders(in: ["nameShort": "Example Editor"]).isEmpty)
        for name in ["", ".", "..", ".hidden", "../Documents", "Example/Editor"] {
            #expect(ProductFolders.vsCodeFolders(in: ["nameShort": name, "dataFolderName": ".x"]).count == 1, "\(name)")
        }
        #expect(ProductFolders.believes(data))
        #expect(!ProductFolders.believes(ProductFolder(path: data.path, proof: nil, work: data.work)))
        #expect(!ProductFolders.believes(ProductFolder(path: "Library/Caches/Example Editor", proof: data.proof, work: data.work)))
        #expect(!ProductFolders.believes(ProductFolder(path: "Library/Application Support/..", proof: data.proof, work: data.work)))
    }

    @Test func believesAFolderReadBackOnlyAsTheRulesNameIt() {
        let ide = ProductFolders.jetBrainsFolders(in: ["productVendor": "ExampleVendor", "dataDirectoryName": "ExampleIDE2025.2"])
        let editor = ProductFolders.vsCodeFolders(in: ["dataFolderName": ".example-editor"])

        #expect((ide + editor).allSatisfy(ProductFolders.believes))
        #expect(!ProductFolders.believes(ProductFolder(path: ide[0].path, proof: nil)))
        #expect(!ProductFolders.believes(ProductFolder(path: ".example-editor", proof: nil)))
        #expect(!ProductFolders.believes(ProductFolder(path: "Documents", proof: nil)))
        #expect(!ProductFolders.believes(ProductFolder(path: "Library/Caches/ExampleVendor/Chrome", proof: nil)))
    }

    @Test func believesOnlyTheNamesTheToolsWrite() {
        let ide = { (vendor: String, name: String) in
            ProductFolders.jetBrainsFolders(in: ["productVendor": vendor, "dataDirectoryName": name])
        }
        #expect(ide("ExampleVendor", "Chrome").isEmpty)
        #expect(ide("../ExampleVendor", "ExampleIDE2025.2").isEmpty)
        #expect(ide("ExampleVendor", "../ExampleIDE2025.2").isEmpty)
        #expect(ide(".ExampleVendor", "ExampleIDE2025.2").isEmpty)
        for name in ["example", ".", "..", ".config/example", ""] {
            #expect(ProductFolders.vsCodeFolders(in: ["dataFolderName": name]).isEmpty, "\(name)")
        }
    }
}
