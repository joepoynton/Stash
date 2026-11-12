//
//  SpreadsheetImportView.swift
//  Stash
//
//  1.3 spreadsheet import flow, opened from Settings › Data (spec B2).
//  Start screen → "Match your columns" → preview. The parsing and planning
//  it sits on live in the other files in this folder.
//

import SwiftUI
import UniformTypeIdentifiers

enum SpreadsheetImportStep: Hashable {
    case columns
    case preview
    case allRows
    case help
}

struct SpreadsheetImportView: View {
    /// Hands a Stash backup (a JSON file made with Export Data) to Settings'
    /// restore path instead of failing.
    var onRestore: (Data) -> Void
    /// Called after a successful import with the message for the result alert.
    var onFinished: (String) -> Void
    /// A file that arrived from outside (Files, Mail, the share sheet). The
    /// flow starts with it already loaded instead of waiting for Choose File.
    var openedFile: ImportOpenedFile? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var model = SpreadsheetImportModel()
    @State private var path: [SpreadsheetImportStep] = []
    @State private var showFilePicker = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var templateURL: URL?
    @State private var showTemplateShare = false
    @State private var handledOpenedFile = false

    private static var pickerTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText, .json]
        let documentTypes = [
            UTType("org.openxmlformats.spreadsheetml.sheet"),
            UTType("com.microsoft.excel.xls"),
            UTType("com.apple.iwork.numbers.sffnumbers"),
            UTType(filenameExtension: "xlsx"),
            UTType(filenameExtension: "xls"),
            UTType(filenameExtension: "numbers"),
        ]
        for type in documentTypes.compactMap({ $0 }) where !types.contains(type) { types.append(type) }
        return types
    }

    var body: some View {
        NavigationStack(path: $path) {
            startScreen
                .navigationTitle("Import from Spreadsheet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(for: SpreadsheetImportStep.self) { step in
                    switch step {
                    case .columns:
                        ImportColumnsView(model: model) { path.append(.preview) }
                    case .preview:
                        ImportPreviewView(model: model, showAllRows: { path.append(.allRows) }) { message in
                            onFinished(message)
                            dismiss()
                        }
                    case .allRows:
                        ImportAllRowsView(model: model)
                    case .help:
                        ImportHelpView()
                    }
                }
        }
        .tint(.teal)
    }

    // MARK: - Start screen

    private var startScreen: some View {
        Form {
            Section {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose File", systemImage: "doc.text")
                }

                HStack {
                    Label("Paste Rows", systemImage: "doc.on.clipboard")
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        load { try SpreadsheetParser.parse(text: text) }
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .tint(.teal)
                }
            } header: {
                Text("Bring in a list")
            } footer: {
                Text("Choose a CSV file from Numbers, Excel or Google Sheets. Or copy the cells in your spreadsheet, come back here and tap Paste. You'll see everything before it's added.")
            }

            Section {
                Button {
                    shareTemplate()
                } label: {
                    Label("Get Template", systemImage: "square.and.arrow.up")
                }
                NavigationLink(value: SpreadsheetImportStep.help) {
                    Label("How does this work?", systemImage: "questionmark.circle")
                }
            } footer: {
                Text("The template is an example file you can fill in and bring back.")
            }
        }
        .disabled(isLoading)
        .task {
            guard let openedFile, !handledOpenedFile else { return }
            handledOpenedFile = true
            switch openedFile {
            case .data(let data, let fileExtension): process(data: data, fileExtension: fileExtension)
            case .failed(let message): errorMessage = message
            }
        }
        .overlay {
            if isLoading { ProgressView().controlSize(.large) }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: Self.pickerTypes) { result in
            handlePicked(result)
        }
        .sheet(isPresented: $showTemplateShare, onDismiss: removeTemplateFile) {
            if let templateURL { ImportShareSheet(url: templateURL) }
        }
        .alert("Can't Import", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - File

    private func handlePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            errorMessage = "Could not open the file."
            return
        }
        switch ImportFileReader.read(url) {
        case .data(let data, let fileExtension): process(data: data, fileExtension: fileExtension)
        case .failed(let message): errorMessage = message
        }
    }

    /// Sends a file's contents on: a Stash backup goes to the restore path,
    /// anything else is read as a spreadsheet.
    private func process(data: Data, fileExtension: String) {
        let isJSONFile = fileExtension == "json"
        let looksLikeJSON = isJSONFile
            || data.first(where: { !" \n\r\t".utf8.contains($0) }) == UInt8(ascii: "{")
        if looksLikeJSON {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if object["areas"] != nil {
                    onRestore(data)
                    dismiss()
                } else {
                    errorMessage = "This JSON file isn't a Stash backup. To bring in a list, save it as CSV or use Paste Rows."
                }
                return
            }
            if isJSONFile {
                errorMessage = "This JSON file couldn't be read."
                return
            }
        }
        load { try SpreadsheetParser.parse(data: data) }
    }

    // MARK: - Loading

    /// Parses off the main actor, then moves on to matching columns.
    private func load(_ work: @escaping @Sendable () throws -> ParsedSpreadsheet) {
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
            isLoading = false
            switch result {
            case .success(let parsed):
                model.load(parsed)
                path = [.columns]
            case .failure(let error):
                errorMessage = (error as? SpreadsheetParseError)?.message ?? "This file couldn't be read."
            }
        }
    }

    // MARK: - Template

    private func shareTemplate() {
        guard let url = ImportTemplate.writeTemporaryFile() else {
            errorMessage = "Couldn't create the template file."
            return
        }
        templateURL = url
        showTemplateShare = true
    }

    private func removeTemplateFile() {
        if let templateURL { try? FileManager.default.removeItem(at: templateURL) }
        templateURL = nil
    }
}

// MARK: - Reading a file

/// A file's contents ready for the flow, or why it couldn't be read.
enum ImportOpenedFile {
    case data(Data, fileExtension: String)
    case failed(String)
}

enum ImportFileReader {

    /// Excel and Numbers documents can be picked (so a folder of them doesn't
    /// look empty) and then explained, because Stash only reads text.
    static let spreadsheetDocumentExtensions: Set<String> = ["xlsx", "xlsm", "xls", "numbers"]

    /// Reads a file chosen in the picker or handed over by another app,
    /// checking the size first so a huge file never gets loaded.
    static func read(_ url: URL) -> ImportOpenedFile {
        let fileExtension = url.pathExtension.lowercased()

        if spreadsheetDocumentExtensions.contains(fileExtension) {
            return .failed(SpreadsheetParseError.spreadsheetDocument.message)
        }

        // Files picked in place need this; a copy in Stash's own Inbox doesn't
        // (the call just returns false).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > SpreadsheetParser.maxBytes {
            return .failed(SpreadsheetParseError.tooLarge.message)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failed("Could not read the file.")
        }
        return .data(data, fileExtension: fileExtension)
    }
}
