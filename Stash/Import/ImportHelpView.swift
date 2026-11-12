//
//  ImportHelpView.swift
//  Stash
//
//  1.3 spreadsheet import (spec B9). Short, plain help for the import flow.
//

import SwiftUI

struct ImportHelpView: View {

    private struct Point: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let text: String
    }

    private let points: [Point] = [
        Point(id: 0, icon: "tablecells", title: "Any spreadsheet works",
              text: "You'll match its columns to Stash on the next screen."),
        Point(id: 1, icon: "mappin.and.ellipse", title: "Only the item name is required",
              text: "Locations can be one column (Garage > Shelf 2) or several (Room, Cupboard, Shelf)."),
        Point(id: 2, icon: "doc.text", title: "Saving a CSV file",
              text: "Numbers: tap the ⋯ button, then Export, then CSV. Excel and Google Sheets have a similar option to export or download as CSV. Then tap Choose File, or pick Stash from the share sheet."),
        Point(id: 3, icon: "doc.on.clipboard", title: "Or skip the file",
              text: "Select the cells, copy them, come back here and tap Paste Rows."),
        Point(id: 4, icon: "square.stack", title: "One sheet at a time",
              text: "Extra columns, such as brand or size, can be added to the item's notes."),
        Point(id: 5, icon: "eye", title: "You'll see everything first",
              text: "Nothing is added until you tap Import. Matching spaces are reused, not duplicated."),
    ]

    var body: some View {
        List {
            ForEach(points) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.icon)
                        .foregroundStyle(.teal)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.title)
                            .font(.subheadline.weight(.semibold))
                        Text(point.text)
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("How Does This Work?")
        .navigationBarTitleDisplayMode(.inline)
    }
}
