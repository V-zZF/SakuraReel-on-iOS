//
//  TMDbRemoteImage.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

struct TMDbRemoteImage: View {
    let path: String?
    var role = "poster"
    var width = 185
    var cachedConfiguration = false
    var placeholderColor: Color = .secondary
    @State private var model = RemoteArtworkModel()
    private var identity: String { "\(path ?? ""):\(role):\(width)" }
    var body: some View {
        Group {
            if let bytes = model.data, let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(placeholderColor) } }
        }
        .clipped().accessibilityHidden(true)
        .task(id: identity) {
            let environment = TMDbEnvironment.shared
            await model.load(path: path, role: role, pixels: width, cachedConfiguration: cachedConfiguration, service: environment.service, images: environment.images)
        }
    }
}
