// swift-tools-version: 6.1

import PackageDescription

// Every dependency resolves from its published URL. NEVER from a `../<name>` sibling.
//
// The old helper preferred a sibling checkout when one existed, so the fleet would share the
// single OCCT.xcframework instead of each repo extracting its own (SecondMouseAU/ecosystem#8).
// The saving is real but bought in the wrong currency: a path dependency carries no version
// requirement, so SwiftPM compiles whatever happens to be checked out in that sibling and drops
// the pin from Package.resolved entirely. Committing that lockfile makes the repo unresolvable
// from any clean checkout, which is CI and every new clone.
//
// Not hypothetical: PadCAM's `main` was unresolvable for exactly this reason and nobody noticed,
// because everyone builds with siblings present. Four incidents in two days built stale sibling
// source (ecosystem#48), and four OCCTParts branches shipped a Package.resolved with every
// occtswift pin stripped, caught by a review bot reading the diff rather than by any check
// (ecosystem#51).
//
// Measured, which is what settles it: the artifact DOWNLOAD is already shared, in
// ~/Library/Caches/org.swift.swiftpm/artifacts, so a URL-resolved build reports
// "Fetched ... from cache" and touches no network. Sibling resolution only ever saved the
// per-project EXTRACTION, about 594 MB in .build/artifacts/. That is disk worth paying for a
// lockfile that means what it says, and it is separately recoverable by sharing the extraction
// (symlink or APFS clone) without substituting source at all.
//
// Ed's rule, 2026-08-20: nothing resolves locally except binaries, and the binary is already
// shared by the artifact cache. The helper is kept rather than reverted to a bare
// `.package(url:)` so the call sites stay identical across the fleet.
func occtDep(_ name: String, from version: String) -> Package.Dependency {
    .package(url: "https://github.com/SecondMouseAU/\(name).git", from: Version(version)!)
}

let package = Package(
    name: "OCCTSwiftTools",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v1),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "OCCTSwiftTools",
            targets: ["OCCTSwiftTools"]
        ),
    ],
    dependencies: [
        occtDep("OCCTSwift", from: "3.0.0"),    // ≥3.0.0: Rule 2 major on a much smaller surface than 2.0.0 (docs/SEMVER.md#v300). OCCT itself does not move: the kernel stays at 8.0.1, rebuilt as v3.0.0-kernel.1 to carry two patches the 2.0.0 asset was missing (OCCTSwift#905/#913). Three breaks, every one audited here and none of them reachable: Selector.SubShapeType.compsolid renamed .compSolid (#844); Shape.ShapeFilterType.RawValue moving Int32 to Int now that ShapeFilterType is a ShapeType typealias (#844), a break only where the raw type is named or stored; and Shape.bounds/size/center, Wire.bounds, Edge.bounds, Face.bounds/exactBounds becoming Optional (#943), returning nil on OCCT's own Bnd_Box::IsVoid() instead of fabricating a (0,0,0)-(0,0,0) box that was indistinguishable from a genuine zero-size shape at the world origin. That third one is what bites elsewhere in the fleet, but nothing here asks a shape for its extent: this repo is a Shape/ViewportBody bridge over meshes, edge polylines and the identity tables, and the ShapeMeasurements it hangs on CADBodyMetadata are computed inside OCCTSwift, not recomputed from bounds here. Verified by a build against the real v3.0.0 sibling rather than grep alone (grep is unreliable on .bounds/.size/.center, which collide with Viewport and SIMD types): floor bump only, zero source changes; ≥2.0.0: correctness release (OCCTSwift#377/#669), OCCT absorbed to 8.0.1. 17 breaking changes (docs/SEMVER.md#v200); audited every call site in this repo against the full break table (issue #51). Shape.faces() and Mesh.Triangle.faceIndex both moved to the deduplicated enumeration together (#541/#613), which the FaceIdentityTable comments below described as a raw-vs-deduplicated split that no longer exists post-2.0.0 (comments updated, no logic change: makeFaceIdentityTable already reads shape.faces() dynamically rather than hardcoding the old enumeration). AAG / mass-property / continuity / PathParser surfaces are not reachable from this repo (grep-verified, zero hits); ≥1.17.0: Pass 1a duplication/bug-fix audit (OCCTSwift#377/#380): continuity enum consolidation (source-compatible via deprecated aliases), Surface.drawMesh/evaluateGrid now return SurfaceGrid (not used here); ≥1.15.0: TopologyGraph renamed to BRepGraph (OCCTSwift#333)
        occtDep("OCCTSwiftViewport", from: "1.2.0"),
        occtDep("OCCTSwiftIO", from: "1.7.8"),  // ≥1.7.0: ShapeLoader splits multibody into per-body entries (#21)
    ],
    targets: [
        .target(
            name: "OCCTSwiftTools",
            dependencies: [
                .product(name: "OCCTSwift",         package: "OCCTSwift"),
                .product(name: "OCCTSwiftViewport", package: "OCCTSwiftViewport"),
                .product(name: "OCCTSwiftIO",       package: "OCCTSwiftIO"),
            ],
            path: "Sources/OCCTSwiftTools",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OCCTSwiftToolsTests",
            dependencies: ["OCCTSwiftTools"],
            path: "Tests/OCCTSwiftToolsTests"
        ),
    ]
)
