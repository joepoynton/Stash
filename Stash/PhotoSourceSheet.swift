//
//  PhotoSourceSheet.swift
//  Stash
//
//  Small bottom sheet for choosing a photo source or removing a photo.
//  Replaces confirmationDialog for photo actions to anchor presentation
//  consistently at the bottom on all device sizes.
//

import SwiftUI

struct PhotoSourceSheet: View {
    let hasPhoto: Bool
    let onCamera: () -> Void
    let onLibrary: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if cameraAvailable {
                actionRow(title: "Take Photo", icon: "camera.fill") {
                    onCamera()
                    dismiss()
                }
                Divider().padding(.leading, 56)
            }

            actionRow(title: "Choose from Library", icon: "photo.on.rectangle") {
                onLibrary()
                dismiss()
            }

            if hasPhoto {
                Divider()
                actionRow(title: "Remove Photo", icon: "trash", destructive: true) {
                    onRemove()
                    dismiss()
                }
            }

            // Breathing room above the home indicator
            Spacer(minLength: 8)
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)  // using our own above
        .presentationCornerRadius(20)
    }

    private var sheetHeight: CGFloat {
        let indicatorArea: CGFloat = 30
        let rowHeight: CGFloat     = 56
        let bottomPad: CGFloat     = 20
        var rows: CGFloat          = 1  // library is always present
        if cameraAvailable { rows += 1 }
        if hasPhoto        { rows += 1 }
        return indicatorArea + (rows * rowHeight) + bottomPad
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(destructive ? Color.red : Color(.label))
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
