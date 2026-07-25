//
//  ContentView.swift
//  PSN CRM
//
//  Created by Rostyslav Triodial on 04.06.2026.
//

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var isLoading = true

    var body: some View {
        ZStack {
            WebView(url: URL(string: "https://crm.poehalisnami.ua")!)
        }
    }
}

#Preview {
    ContentView()
}
