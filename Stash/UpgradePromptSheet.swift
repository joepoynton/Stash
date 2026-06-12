//
//  UpgradePromptSheet.swift
//  Stash
//
//  Reusable upgrade sheet shown whenever a free-tier limit is hit.
//  Pass a contextual `message` explaining why the prompt appeared.
//  Price is fetched live from StoreKit — no hardcoded values.
//

import SwiftUI
import StoreKit

struct UpgradePromptSheet: View {
    /// Contextual sentence shown beneath the title — e.g. item count info.
    let message: String

    @Environment(\.dismiss) private var dismiss
    @Environment(StoreKitManager.self) private var storeKit

    @State private var isPurchasing = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Icon
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.teal)
                        .padding(.top, 32)

                    // Title + message
                    VStack(spacing: 10) {
                        Text("Stash Pro")
                            .font(.title).bold()

                        Text(message)
                            .font(.body)
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Feature list
                    VStack(alignment: .leading, spacing: 14) {
                        ProFeatureRow(icon: "infinity",
                                      text: "Unlimited items")
                        ProFeatureRow(icon: "camera.fill",
                                      text: "Photos on items and locations")
                        ProFeatureRow(icon: "square.and.arrow.up",
                                      text: "Data export (JSON)")
                    }
                    .padding(.horizontal, 40)

                    // Purchase button
                    Button {
                        Task {
                            isPurchasing = true
                            await storeKit.purchase()
                            isPurchasing = false
                            if storeKit.isPro { dismiss() }
                        }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(purchaseLabel)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(isPurchasing || isRestoring)
                    .padding(.horizontal, 32)

                    // Restore purchases
                    Button {
                        Task {
                            isRestoring = true
                            await storeKit.restorePurchases()
                            isRestoring = false
                            if storeKit.isPro { dismiss() }
                        }
                    } label: {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore Purchases")
                                .font(.subheadline)
                                .foregroundStyle(.teal)
                        }
                    }
                    .disabled(isPurchasing || isRestoring)

                    // Error
                    if let error = storeKit.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Informational status (e.g. Ask to Buy pending)
                    if let message = storeKit.purchaseMessage {
                        Label(message, systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var purchaseLabel: String {
        if let product = storeKit.product {
            return "Unlock Stash Pro — \(product.displayPrice)"
        }
        return "Unlock Stash Pro"
    }
}

private struct ProFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 22)
            Text(text)
                .font(.body)
        }
    }
}
