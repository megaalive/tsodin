package compat

// Compatibility is an explicit, independently tested language contract.
// Scanner/parser/checker code consumes a Profile instead of checking TS
// version numbers throughout the compiler.
//
// INVARIANT: registering a new TypeScript release requires an independent
// version-specific oracle gate. Do not auto-promote a new major version.

Scanner_Edition :: enum {
    ASCII_Subset_V1,
}

Version :: struct {
    major: u16,
    minor: u16,
    patch: u16,
}

Profile :: struct {
    version: Version,
    scanner_edition: Scanner_Edition,
}

// The sole registered TypeScript reference while M1 is in progress.
ts7_profile :: proc() -> Profile {
    return Profile {
        version = Version{7, 0, 2},
        scanner_edition = .ASCII_Subset_V1,
    }
}

// Unknown versions are unsupported, not silently assumed compatible.
// Future TS8 support should add its profile here after separate oracle tests.
profile_is_registered :: proc(profile: Profile) -> bool {
    return profile.version.major == 7 &&
           profile.version.minor == 0 &&
           profile.version.patch == 2 &&
           profile.scanner_edition == .ASCII_Subset_V1
}

profile_resolve :: proc(major, minor, patch: u16) -> (Profile, bool) {
    profile := Profile{version = Version{major, minor, patch},
                       scanner_edition = .ASCII_Subset_V1}
    if !profile_is_registered(profile) {
        return Profile{}, false
    }
    return profile, true
}
