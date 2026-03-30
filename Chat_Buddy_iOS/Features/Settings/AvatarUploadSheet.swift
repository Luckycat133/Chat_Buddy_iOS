import SwiftUI
import PhotosUI

/// Allows users to select a photo, crop it to a circle, and save as base64 avatar.
struct AvatarUploadSheet: View {
    let currentAvatar: String?   // existing base64, may be nil
    let onSave: (String) -> Void // returns base64 JPEG
    let onDismiss: () -> Void

    @Environment(LocalizationManager.self) private var localization

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var errorMessage: String?

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private let cropSize: CGFloat = 256

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.lg) {
                // Preview
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: cropSize, height: cropSize)

                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(scale)
                            .offset(offset)
                            .frame(width: cropSize, height: cropSize)
                            .clipShape(Circle())
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { v in scale = max(0.5, min(2.0, v.magnification)) }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { v in offset = v.translation }
                            )
                    } else if let existing = currentAvatar,
                              let data = Data(base64Encoded: existing),
                              let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cropSize, height: cropSize)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                )

                // Picker
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(isZh ? "选择照片" : "Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedItem) { _, newItem in
                    loadImage(from: newItem)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(DSTypography.caption1)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(DSSpacing.lg)
            .navigationTitle(isZh ? "更换头像" : "Change Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "保存" : "Save") {
                        saveAvatar()
                    }
                    .disabled(selectedImage == nil)
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    // Check size limit (5 MB raw)
                    if data.count > 5 * 1_048_576 {
                        errorMessage = isZh ? "图片大小不能超过 5MB" : "Image must be under 5 MB"
                        return
                    }
                    selectedImage = img
                    errorMessage = nil
                    scale = 1.0
                    offset = .zero
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAvatar() {
        guard let image = selectedImage else { return }

        // Render cropped circle at 256×256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        let cropped = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: 256, height: 256))
            UIBezierPath(ovalIn: rect).addClip()

            let imgSize = image.size
            let drawScale = max(256 / imgSize.width, 256 / imgSize.height) * scale
            let drawW = imgSize.width * drawScale
            let drawH = imgSize.height * drawScale
            let drawX = (256 - drawW) / 2 + offset.width
            let drawY = (256 - drawH) / 2 + offset.height

            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }

        guard let jpegData = cropped.jpegData(compressionQuality: 0.9) else {
            errorMessage = isZh ? "图片处理失败" : "Image processing failed"
            return
        }

        let base64 = jpegData.base64EncodedString()
        onSave(base64)
    }
}
