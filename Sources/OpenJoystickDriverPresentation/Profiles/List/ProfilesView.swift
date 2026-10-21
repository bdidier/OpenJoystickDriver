#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  struct ProfilesView: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    @ObservedObject
    var library: ProfileLibraryModel
    @ObservedObject
    var navigation: MainWindowNavigationModel
    @ObservedObject
    var screen: ProfilesViewModel
  }

#endif
