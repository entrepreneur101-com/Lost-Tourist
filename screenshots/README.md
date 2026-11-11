Lost? Where am I?
A simple app for tourists who are lost. Take a photo of where you are, and the app tells you the place name and address, translates any signs, and reads a short story about the place aloud.
It is built for people who are lost, not people planning a route: big text, one button per screen, nothing confusing.
Status: early prototype. The app builds and installs on Android, but it is not finished. See "What works" below.
Screens (design mockups)
These are design mockups, not photos of the running app.
<img src="screenshots/1-home.jpg" width="180"> <img src="screenshots/2-scanning.jpg" width="180"> <img src="screenshots/3-you-are-here.jpg" width="180">
<img src="screenshots/4-narrator.jpg" width="180"> <img src="screenshots/5-paywall.jpg" width="180">
How it works
You take a photo. The app also gets your GPS position.
Signs in the photo are read on your phone, and translated on your phone.
A small server looks up the nearest matching place using Google Places and returns the name and address.
The narrator reads a short description aloud using your phone's built-in voice.
What works and what doesn't
Working: all screens, the camera, GPS, sign reading and translation (to English), the narrator voice, and the free-scans counter.
Not finished: the server address is a placeholder, so lookups fail until you set up your own server.
Placeholder: the 14-day pass button does not take real payment. It grants the pass for free until a payment service is added.
Tech
Flutter app (Android first)
On-device text reading and translation (Google ML Kit) and on-device narration (text-to-speech)
A small Cloudflare Worker that keeps the Google Places key off the phone
Build it yourself
Install Flutter and run flutter pub get.
Deploy the server code to a Cloudflare Worker, add your own Google Places API key as a secret named GOOGLE_KEY, and put the Worker's address in backendUrl in lib/main.dart.
Run flutter run on a real phone. The camera and GPS need one.
Never put an API key in this repo.
Contributing
Ideas, bug reports and pull requests are welcome. Please open an issue first for big changes.
License
MIT. See the LICENSE file.
