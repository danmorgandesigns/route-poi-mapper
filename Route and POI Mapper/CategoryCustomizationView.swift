//
//  CategoryCustomizationView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/11/25.
//

import SwiftUI

struct CategoryCustomizationView: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var newCategoryName = ""
    @State private var showingDeleteAlert = false
    @State private var categoryToDelete: String?
    
    var body: some View {
        NavigationView {
            VStack {
                // Add new category section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add New Category")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack {
                        TextField("Category name", text: $newCategoryName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.words)
                        
                        Button("Add") {
                            addCategory()
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
                
                Divider()
                    .padding(.vertical)
                
                // Categories list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Categories")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if dataManager.customCategories.isEmpty {
                        Text("No categories yet")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        List {
                            ForEach(dataManager.customCategories.sorted(), id: \.self) { category in
                                HStack {
                                    Text(category)
                                    Spacer()
                                    Button(action: {
                                        categoryToDelete = category
                                        showingDeleteAlert = true
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Customize Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .alert("Delete Category", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    dataManager.removeCustomCategory(category)
                }
            }
        } message: {
            if let category = categoryToDelete {
                Text("Are you sure you want to delete '\(category)'?")
            }
        }
    }
    
    private func addCategory() {
        dataManager.addCustomCategory(newCategoryName)
        newCategoryName = ""
    }
}

#Preview {
    CategoryCustomizationView(dataManager: DataManager())
}
