//
//  OnboardingView.swift
//  iShareBudget
//
//  Paged intro shown once to new users. Presented as a fullScreenCover from RootTabView.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !viewModel.isLastPage {
                    Button("Пропустить") {
                        viewModel.skip()
                        dismiss()
                    }
                    .padding()
                }
            }
            .frame(height: 44)

            TabView(selection: $viewModel.currentPage) {
                ForEach(viewModel.pages) { page in
                    OnboardingPageView(page: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                withAnimation {
                    let wasLastPage = viewModel.isLastPage
                    viewModel.advance()
                    if wasLastPage {
                        dismiss()
                    }
                }
            } label: {
                Text(viewModel.isLastPage ? "Начать" : "Далее")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: page.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Color(hex: page.colorHex))
                    .clipShape(Circle())

                VStack(spacing: 8) {
                    Text(LocalizedStringKey(page.title))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(LocalizedStringKey(page.message))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView()
}

#Preview("Onboarding — Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
