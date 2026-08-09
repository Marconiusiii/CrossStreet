//
//  OnboardingView.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import SwiftUI

struct OnboardingView: View {
	var locationProvider: LocationProvider
	var onComplete: () -> Void

	@State private var path: [Int] = []
	@State private var isRequestingPermission = false

	private let pages = [
		OnboardingPage(
			title: "Welcome to Intersector",
			body: "Intersector helps you identify nearby intersections and orient yourself by street direction. It is built for quick, accessible street context from the app or Siri."
		),
		OnboardingPage(
			title: "Use Siri Shortcuts",
			body: "Try saying: Nearest intersection in Intersector. Upcoming intersection in Intersector. Start Scan Mode in Intersector. You can also set up your own shortcuts using Intersector in the Shortcuts app."
		),
		OnboardingPage(
			title: "Apple Watch Support",
			body: "Apple Watch support is included. If Intersector does not appear on your watch automatically, open the Watch app on iPhone and install it from Available Apps."
		),
		OnboardingPage(
			title: "Location Permission",
			body: "Intersector needs your location to find the streets and intersections around you. The next step opens the iOS location permission request."
		)
	]

	var body: some View {
		NavigationStack(path: $path) {
			pageView(for: 0)
				.navigationDestination(for: Int.self) { page in
					pageView(for: page)
				}
		}
		.tint(Color.crossAccent)
	}

	private func pageView(for page: Int) -> some View {
		OnboardingPageView(
			page: pages[page],
			isRequestingPermission: isRequestingPermission,
			onNext: {
				goNext(from: page)
			}
		)
		.navigationBarBackButtonHidden(true)
		.toolbar(.hidden, for: .navigationBar)
	}

	private func goNext(from page: Int) {
		if page < pages.count - 1 {
			path.append(page + 1)
			return
		}

		isRequestingPermission = true
		Task {
			_ = await locationProvider.requestWhenInUseAuthorization()
			isRequestingPermission = false
			onComplete()
		}
	}
}

private struct OnboardingPageView: View {
	var page: OnboardingPage
	var isRequestingPermission: Bool
	var onNext: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 24) {
			Spacer(minLength: 0)
			Text(page.title)
				.font(.largeTitle)
				.fontWeight(.bold)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
			Text(page.body)
				.font(.title3)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
			Button {
				onNext()
			} label: {
				Text(isRequestingPermission ? "Requesting..." : "Next")
					.font(.title3)
					.fontWeight(.semibold)
					.foregroundStyle(Color.crossButtonText)
					.multilineTextAlignment(.center)
					.lineLimit(nil)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 18)
			}
			.buttonStyle(.borderedProminent)
			.disabled(isRequestingPermission)
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.background(Color.crossBg)
	}
}

private struct OnboardingPage {
	var title: String
	var body: String
}
