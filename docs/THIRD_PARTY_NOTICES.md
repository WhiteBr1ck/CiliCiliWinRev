# Third-party notices

Update downloads use Dart's crypto (BSD-3-Clause) and cryptography (Apache-2.0) packages for SHA256 and Ed25519 verification. Their license notices are included in Flutter's generated license registry. Publisher tooling uses the official WinSparkle 0.9.4 signing utility, https://github.com/vslavik/winsparkle/releases/tag/v0.9.4, under its MIT-style license. The application does not bundle the WinSparkle runtime or its native update dialogs.

CiliCiliWinRev is an independent Flutter Windows client. It is not an official CLICLI release.

The catalog, playback information and danmaku are served by CLICLI. This implementation was verified against the HTTP protocol of the user-provided CLICLI Windows 1.1.5 application. That application declares an MIT license in its bundled package.json. The original application binaries and UI code are not included in this distribution.

Cover artwork is obtained from the catalog image URL. When it is unavailable, this client can obtain an exact title and season match from the public Bangumi API, https://api.bgm.tv/. Artwork remains the property of its respective owners. No fabricated images or ratings are used.

Quarter schedules and broadcast-day metadata also use the public Bangumi API. Schedule inclusion does not imply availability in the CLICLI catalog.

Broadcast instants are supplemented using the public AniList GraphQL API, https://graphql.anilist.co/ and https://anilist.co/. Entries are matched by exact normalized titles with season identity preserved. Timestamps are displayed in the computer's local timezone. No AniList artwork is redistributed.

Noto Sans SC is distributed under the SIL Open Font License 1.1. The complete license is included at data/flutter_assets/assets/fonts/OFL.txt. Static 400, 600 and 700 weight instances were generated from the Google Fonts Noto Sans SC variable font with fontTools. These fonts have vector outlines and are not copies of proprietary Windows fonts.

The application uses Flutter and Dart (BSD-style licenses), media_kit and media_kit_video (MIT), libmpv and its video decoding dependencies, and the packages listed in pubspec.lock. The Windows media_kit binary distribution is provided by https://github.com/media-kit/libmpv-win32-video-build/releases. The linked media_kit release uses GPL/LGPL components; their corresponding source and build instructions are available in that repository and its build references. Preserve these notices when redistributing the package.

Flutter's bundled NOTICES.Z file contains the generated license registry for Dart packages and framework dependencies. It is included under data/flutter_assets in the portable distribution.

The portable distribution also includes the Microsoft Visual C++ runtime DLLs selected by CMake from the installed Visual Studio redistributable directory.

Animeko (https://github.com/open-ani/animeko) was consulted as a behavioral reference for in-frame controls and adaptive player panels, at commit 184badb61515899f85ba89d2d35b6e01a24d7e78. Its UI source is not included or translated into this client. The new circular C/play icon is generated from this project's own drawing instructions.


The Windows installer is generated with Inno Setup 7.1.0, Copyright (C) 1997-2026 Jordan Russell and portions Copyright (C) 2000-2026 Martijn Laan. Project and license: https://jrsoftware.org/ and https://github.com/jrsoftware/issrc/blob/is-7_1_0/license.txt. Installer code and language resources remain those of the Inno Setup project.
