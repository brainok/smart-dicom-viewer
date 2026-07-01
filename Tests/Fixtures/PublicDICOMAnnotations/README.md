# Public DICOM Annotation Fixtures

These files are used for local parser and rendering validation of DICOM-derived annotation objects.

## OFFIS / DCMTK GSPS

- Source page: https://support.dcmtk.org/redmine/issues/1042
- Image: https://support.dcmtk.org/redmine/attachments/download/191/image_256x256_16x16_1.0x1.0.dcm
- Presentation state: https://support.dcmtk.org/redmine/attachments/download/190/gsps_256x256_16x16_1.0x1.0.dcm
- Purpose: Grayscale Softcopy Presentation State graphic annotation alignment test.
- Note: These are public Redmine issue attachments. The issue page does not state an explicit redistribution license.

## pydicom RTSTRUCT

- Source repository: https://github.com/pydicom/pydicom
- File source: https://raw.githubusercontent.com/pydicom/pydicom/f15214fb9bc83d063f481552c487b02b28bfb7cc/src/pydicom/data/test_files/rtstruct.dcm
- Purpose: RT Structure Set parser fixture. This file lacks a DICOM Part 10 preamble, so it also validates non-preamble DICOM dataset parsing.
- License: pydicom is MIT licensed; its test-file README states that test data are freely usable for testing.

## highdicom DICOM SEG

- Source repository: https://github.com/ImagingDataCommons/highdicom
- File source: https://raw.githubusercontent.com/ImagingDataCommons/highdicom/master/data/test_files/seg_image_ct_binary.dcm
- Purpose: Native binary DICOM Segmentation Storage parser fixture with per-frame source-image references.
- License: highdicom is MIT licensed.
