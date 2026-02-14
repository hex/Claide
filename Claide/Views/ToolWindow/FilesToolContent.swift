// ABOUTME: Files panel content for the tool window system: file change log.
// ABOUTME: Wraps FileLogPanel with its view model lifecycle.

import SwiftUI

struct FilesToolContent: View {
    @Bindable var viewModel: FileLogViewModel

    var body: some View {
        FileLogPanel(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
