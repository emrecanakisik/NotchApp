//
//  newNotchApp.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI

@main
struct newNotchApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
