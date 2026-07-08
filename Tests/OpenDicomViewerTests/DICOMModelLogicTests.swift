import Foundation
import Testing
import simd
@testable import OpenDicomViewer

private func imageContext(
    orientation: [Double],
    url: URL = URL(fileURLWithPath: "/tmp/test.dcm"),
    seriesUID: String = "series-1",
    numberOfFrames: Int = 1,
    instanceNumber: Int = 1,
    studyInstanceUID: String? = nil,
    modality: String? = nil
) -> DicomImageContext {
    DicomImageContext(
        url: url,
        sopInstanceUID: "1.2.826.0.1.3680043.10.99.1",
        seriesUID: seriesUID,
        seriesDescription: "test",
        instanceNumber: instanceNumber,
        seriesNumber: 1,
        zLocation: nil,
        imagePosition: SIMD3<Double>(0, 0, 0),
        imageOrientation: orientation,
        pixelSpacing: SIMD2<Double>(1, 1),
        sliceThickness: 1.0,
        spacingBetweenSlices: 1.0,
        frameOfReferenceUID: nil,
        studyInstanceUID: studyInstanceUID,
        modality: modality,
        numberOfFrames: numberOfFrames
    )
}

@Test
func crossProduct() {
    let a = SIMD3<Double>(1, 0, 0)
    let b = SIMD3<Double>(0, 1, 0)
    #expect(OpenDicomViewer.cross(a, b) == SIMD3<Double>(0, 0, 1))
}

@Test
func dominantAxisAxial() {
    let series = DicomSeries(
        id: "axial",
        seriesNumber: 1,
        seriesDescription: "axial",
        images: [imageContext(orientation: [1, 0, 0, 0, 1, 0])]
    )
    #expect(series.dominantAxis == .axial)
}

@Test
func dominantAxisCoronal() {
    let series = DicomSeries(
        id: "coronal",
        seriesNumber: 2,
        seriesDescription: "coronal",
        images: [imageContext(orientation: [1, 0, 0, 0, 0, 1])]
    )
    #expect(series.dominantAxis == .coronal)
}

@Test
func dominantAxisSagittal() {
    let series = DicomSeries(
        id: "sagittal",
        seriesNumber: 3,
        seriesDescription: "sagittal",
        images: [imageContext(orientation: [0, 1, 0, 0, 0, 1])]
    )
    #expect(series.dominantAxis == .sagittal)
}

@Test
func seriesThumbnailContextUsesMiddleInstance() {
    let contexts = (0..<5).map { index in
        imageContext(
            orientation: [1, 0, 0, 0, 1, 0],
            url: URL(fileURLWithPath: "/tmp/middle-\(index).dcm"),
            instanceNumber: index + 1
        )
    }
    let series = DicomSeries(id: "middle", seriesNumber: 4, seriesDescription: "middle", images: contexts)

    #expect(series.thumbnailImageContext?.instanceNumber == 3)
}

@Test
func ctThumbnailWindowLevelUsesBrainWindow() {
    let series = DicomSeries(
        id: "ct-pre",
        seriesNumber: 2,
        seriesDescription: "Pre 5mm",
        images: [
            imageContext(
                orientation: [1, 0, 0, 0, 1, 0],
                modality: "CT"
            )
        ]
    )

    let wl = DICOMModel().thumbnailWindowLevel(for: series, min: -1024, max: 3071)
    #expect(wl.width == 80)
    #expect(wl.center == 40)
}

@Test
func ctDefaultWindowLevelUsesBrainWindowForAnyCTDescription() {
    let series = DicomSeries(
        id: "ct-pre",
        seriesNumber: 2,
        seriesDescription: "PRE",
        images: [
            imageContext(
                orientation: [1, 0, 0, 0, 1, 0],
                modality: "CT"
            )
        ]
    )

    let preset = DICOMModel().defaultWindowLevelPreset(for: series)
    #expect(preset?.width == 80)
    #expect(preset?.center == 40)
}

@Test
func defaultWindowLevelPresetsMatchClinicalList() {
    let presets = WindowLevelPreset.defaultPresets
    #expect(presets.map(\.name) == ["Brain", "ASPECTS", "ASPECTS 2", "MIP", "Lung", "Bone", "Angio"])
    #expect(presets[3].center == 250)
    #expect(presets[3].width == 1000)
}

@Test
func mipDefaultWindowLevelUsesMIPPreset() {
    let series = DicomSeries(
        id: "mip",
        seriesNumber: 305,
        seriesDescription: "MIP-S",
        images: [
            imageContext(
                orientation: [1, 0, 0, 0, 1, 0],
                modality: "CT"
            )
        ]
    )

    let preset = DICOMModel().defaultWindowLevelPreset(for: series)
    #expect(preset?.width == 1000)
    #expect(preset?.center == 250)
}

@Test
func mipThumbnailWindowLevelUsesMIPPreset() {
    let series = DicomSeries(
        id: "mip-thumb",
        seriesNumber: 305,
        seriesDescription: "Perfusion 5mm(MAP)",
        images: [
            imageContext(
                orientation: [1, 0, 0, 0, 1, 0],
                modality: "CT"
            )
        ]
    )

    let wl = DICOMModel().thumbnailWindowLevel(for: series, min: -1024, max: 3071)
    #expect(wl.width == 1000)
    #expect(wl.center == 250)
}

@Test
func ctThumbnailWindowingAppliesRescaleInterceptBeforeDisplay() {
    let model = DICOMModel()
    let byte = model.thumbnailDisplayByte(
        storedValue: 1064,
        rescaleSlope: 1,
        rescaleIntercept: -1024,
        windowBottom: 0,
        windowWidth: 80,
        isMonochrome1: false
    )

    #expect(byte >= 126)
    #expect(byte <= 128)
}

@Test
func nonCTThumbnailWindowLevelUsesDataRange() {
    let series = DicomSeries(
        id: "mr",
        seriesNumber: 3,
        seriesDescription: "T2",
        images: [
            imageContext(
                orientation: [1, 0, 0, 0, 1, 0],
                modality: "MR"
            )
        ]
    )

    let wl = DICOMModel().thumbnailWindowLevel(for: series, min: 10, max: 210)
    #expect(wl.width == 200)
    #expect(wl.center == 110)
}

@Test
func numericKeypadKeysMapToWindowLevelPresetIndices() {
    let model = DICOMModel()
    #expect(model.windowLevelPresetIndex(forNumericKeypadKeyCode: 83) == 0)
    #expect(model.windowLevelPresetIndex(forNumericKeypadKeyCode: 84) == 1)
    #expect(model.windowLevelPresetIndex(forNumericKeypadKeyCode: 92) == 8)
    #expect(model.windowLevelPresetIndex(forNumericKeypadKeyCode: 18) == nil)
}

@Test
func tileWindowSlidesOneInstancePastVisibleEdges() {
    #expect(slidingTileStart(currentStart: 0, currentIndex: 8, totalCount: 32, visibleCount: 9) == 0)
    #expect(slidingTileStart(currentStart: 0, currentIndex: 9, totalCount: 32, visibleCount: 9) == 1)
    #expect(slidingTileStart(currentStart: 9, currentIndex: 8, totalCount: 32, visibleCount: 9) == 8)
    #expect(slidingTileStart(currentStart: 8, currentIndex: 7, totalCount: 32, visibleCount: 9) == 7)
}

@Test
func seriesStudyUIDUsesFirstInstanceStudy() {
    let series = DicomSeries(
        id: "study-series",
        seriesNumber: 5,
        seriesDescription: "study",
        images: [
            imageContext(orientation: [1, 0, 0, 0, 1, 0], studyInstanceUID: "study-uid"),
            imageContext(orientation: [1, 0, 0, 0, 1, 0], studyInstanceUID: "study-uid")
        ]
    )

    #expect(series.studyInstanceUID == "study-uid")
}

// MARK: - Multi-frame grouping key

@Test
func groupingKeyForSingleFrameIsSeriesUID() {
    let ctx = imageContext(orientation: [1, 0, 0, 0, 1, 0], numberOfFrames: 1)
    #expect(ctx.seriesGroupingKey == "series-1")
}

@Test
func groupingKeyForMultiFrameIsPerFile() {
    let a = imageContext(
        orientation: [1, 0, 0, 0, 1, 0],
        url: URL(fileURLWithPath: "/tmp/cine-a.dcm"),
        seriesUID: "shared-uid",
        numberOfFrames: 100
    )
    let b = imageContext(
        orientation: [1, 0, 0, 0, 1, 0],
        url: URL(fileURLWithPath: "/tmp/cine-b.dcm"),
        seriesUID: "shared-uid",
        numberOfFrames: 100
    )
    // Two multi-frame files with identical seriesUID must produce distinct keys
    #expect(a.seriesGroupingKey != b.seriesGroupingKey)
    #expect(a.seriesGroupingKey.hasPrefix("shared-uid#mf#"))
    #expect(b.seriesGroupingKey.hasPrefix("shared-uid#mf#"))
}

@Test
func groupingBehaviorSplitsMultiFrameKeepsSingleFrame() {
    // 11 multi-frame cines sharing one SeriesUID + 2 single-frame files sharing another UID
    var contexts: [DicomImageContext] = []
    for i in 0..<11 {
        contexts.append(imageContext(
            orientation: [1, 0, 0, 0, 1, 0],
            url: URL(fileURLWithPath: "/tmp/cine-\(i).dcm"),
            seriesUID: "cine-uid",
            numberOfFrames: 100
        ))
    }
    for i in 0..<2 {
        contexts.append(imageContext(
            orientation: [1, 0, 0, 0, 1, 0],
            url: URL(fileURLWithPath: "/tmp/ct-\(i).dcm"),
            seriesUID: "ct-uid",
            numberOfFrames: 1
        ))
    }
    let grouped = Dictionary(grouping: contexts, by: { $0.seriesGroupingKey })
    // 11 unique cine keys + 1 ct-uid key = 12 groups
    #expect(grouped.count == 12)
    // Each multi-frame group has exactly 1 file
    let cineGroups = grouped.filter { $0.key.hasPrefix("cine-uid#mf#") }
    #expect(cineGroups.count == 11)
    for (_, imgs) in cineGroups { #expect(imgs.count == 1) }
    // Single-frame group has 2 files
    #expect(grouped["ct-uid"]?.count == 2)
}

@Test
func displayDescriptionIncludesFilenameForMultiFrame() {
    let ctx = imageContext(
        orientation: [1, 0, 0, 0, 1, 0],
        url: URL(fileURLWithPath: "/tmp/650.dcm"),
        numberOfFrames: 96
    )
    let desc = ctx.displaySeriesDescription(baseDescription: "Angio")
    #expect(desc.contains("650"))
    #expect(desc.contains("96"))
}

@Test
func displayDescriptionUnchangedForSingleFrame() {
    let ctx = imageContext(orientation: [1, 0, 0, 0, 1, 0], numberOfFrames: 1)
    let desc = ctx.displaySeriesDescription(baseDescription: "CT Chest")
    #expect(desc == "CT Chest")
}
