# Validation

On a Mac with Xcode, run `bash Tests/run-core-tests.sh` from the repository root.
This compiles the production category filters and lookup service against model
fixtures and a mocked URLSession. It does not test SwiftUI, SwiftData, or the camera.

Build the iOS app without publishing:

```sh
xcodebuild -project PantryScanner/Pantry.xcodeproj -scheme SimpleNews \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Device/simulator acceptance checks (pending execution):

1. With an existing installation containing items/lots, upgrade without deleting
   the app. Verify inventory survives the new optional imageURL field. Older
   items show the picture placeholder; newly looked-up items use a product image
   when available.
2. On a supported iPhone, open Add Item and allow camera access. Verify barcode
   recognition and product lookup show distinct messages/spinners. Hold the same
   barcode in frame: only one lookup should occur. Dates can still be recognized.
3. Test a known barcode, an unknown barcode, and airplane mode. Verify found,
   not-found, and failed states, respectively. Retry after reconnecting. An
   unresponsive request should time out; manual entry remains possible afterward.
4. During a slow lookup, close the sheet or select Scan again, then scan a new
   product. The old response must not populate the new form. Save is disabled
   during lookup. Scan again clears product fields; stock settings are retained.
5. Deny camera permission or use an unsupported simulator. Verify manual entry,
   typed barcode lookup, and saving still work. Verify a nil expiration stays
   unset unless tracking is enabled or a date is scanned.
6. Create A, B, and C in different update order. Search for B, swipe Remove, and
   verify only B and its lots disappear. Relaunch and verify deletion persists.
   Repeat from a category list with search applied. Check that pending expiration
   notifications for the deleted item are removed.
7. Tap all four summary buttons. Counts represent product entries, not summed
   quantities. In Stock means quantity > 0; Out of Stock means quantity = 0;
   Low Stock means quantity below a positive par level (including zero stock).
   Expiring Soon includes stocked items with any lot expiring today through
   seven calendar days ahead, excluding already expired lots. Categories overlap.
8. Edit quantity/par/date from a category list, return, and verify membership and
   home counts update. Remove the last matching item and check the empty state.
9. Verify all list rows show only picture/placeholder, name, and quantity. Open
   details to access brand, size, barcode, location, par level, and expiration.
   Check long names, large Dynamic Type, VoiceOver, dark mode, and failed images.

The Windows editing environment has no Swift compiler, Xcode, or iOS simulator;
the Swift checks, build, migration, and device checks must be run on a Mac/device.
