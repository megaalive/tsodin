package compat

import "core:testing"

@(test)
registered_profile_contract :: proc(t: ^testing.T) {
    profile := ts7_profile()
    testing.expect(t, profile_is_registered(profile), "pinned TS7 profile is registered")
    got, ok := profile_resolve(7, 0, 2)
    testing.expect(t, ok && got == profile, "resolution is deterministic")
}

@(test)
unverified_versions_fail_closed :: proc(t: ^testing.T) {
    _, ok := profile_resolve(8, 0, 0)
    testing.expect(t, !ok, "future TS8 is not silently treated as TS7")
    _, ok = profile_resolve(7, 1, 0)
    testing.expect(t, !ok, "new minor requires an explicit compatibility review")
    _, ok = profile_resolve(7, 0, 3)
    testing.expect(t, !ok, "new patch requires an explicit compatibility review")
    testing.expect(t, !profile_is_registered(Profile{}), "zero state is not valid")
    testing.expect(t, !profile_is_registered(Profile{
        version = Version{8, 0, 0},
        scanner_edition = .ASCII_Subset_V1,
    }), "constructing an unregistered profile must not bypass the registry")
}
