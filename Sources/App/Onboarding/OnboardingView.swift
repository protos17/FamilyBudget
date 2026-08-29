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

    private var accentColor: Color {
        Color(hex: viewModel.pages[viewModel.currentPage].colorHex)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.35), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: viewModel.currentPage)

            VStack(spacing: 0) {
                skipBar

                TabView(selection: $viewModel.currentPage) {
                    ForEach(viewModel.pages) { page in
                        OnboardingPageView(page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .tint(accentColor)
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentPage)

                continueButton
            }
        }
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            if !viewModel.isLastPage {
                Button("Пропустить") {
                    viewModel.skip()
                    dismiss()
                }
                .fontDesign(.rounded)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding()
            }
        }
        .frame(height: 44)
    }

    private var continueButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                let wasLastPage = viewModel.isLastPage
                viewModel.advance()
                if wasLastPage {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.isLastPage ? "Начать" : "Далее")
                    .contentTransition(.opacity)
                Image(systemName: viewModel.isLastPage ? "checkmark" : "arrow.right")
                    .contentTransition(.symbolEffect(.replace))
            }
            .fontDesign(.rounded)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(accentColor)
        .padding()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 32)

                ZStack {
                    Circle()
                        .fill(Color(hex: page.colorHex).gradient)
                        .frame(width: 120, height: 120)
                        .shadow(color: Color(hex: page.colorHex).opacity(0.4), radius: 20, y: 10)

                    Image(systemName: page.systemImage)
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: didAppear)
                }

                VStack(spacing: 10) {
                    Text(LocalizedStringKey(page.title))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(LocalizedStringKey(page.message))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { didAppear.toggle() }
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
