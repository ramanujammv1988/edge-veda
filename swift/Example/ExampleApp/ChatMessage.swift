//
//  ChatMessage.swift
//  ExampleApp
//
//  Chat message model
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role: String {
        case user
        case assistant
        case system
    }
    
    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Persona Presets
enum ChatPersona: String, CaseIterable {
    case assistant = "Assistant"
    case coder = "Coder"
    case creative = "Creative"
    
    var systemPrompt: String {
        switch self {
        case .assistant:
            return "You are a helpful AI assistant. Provide clear, concise, and accurate responses."
        case .coder:
            return "You are an expert programmer. Provide technical, precise answers with code examples when relevant."
        case .creative:
            return "You are a creative AI assistant. Be imaginative, expressive, and think outside the box."
        }
    }
    
    var icon: String {
        switch self {
        case .assistant:
            return "person.fill"
        case .coder:
            return "chevron.left.forwardslash.chevron.right"
        case .creative:
            return "sparkles"
        }
    }
}