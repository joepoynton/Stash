//
//  ImportTemplate.swift
//  Stash
//
//  1.3 spreadsheet import (spec B9). The example CSV offered by "Get Template",
//  and the share sheet that hands it over.
//

import SwiftUI
import UIKit

enum ImportTemplate {

    static let fileName = "stash-import-template.csv"

    static let csv = """
    Location,Item,Quantity,Unit,Minimum,Expiry,Notes
    Kitchen > Cupboard by the oven,Paracetamol,2,boxes,1,31/03/2027,
    Garage > Shelf 2,AA batteries,12,,8,,Rechargeable ones are in the drawer
    Studio > Paint cabinet > Drawer 1,Oil paints,,,,,https://www.icloud.com/numbers/example

    """

    /// Writes the template to a temporary file, or nil if that fails. The
    /// caller removes it when the share sheet closes.
    static func writeTemporaryFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// The system share sheet for one file.
struct ImportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
