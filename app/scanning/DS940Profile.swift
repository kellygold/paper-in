import Foundation

/// Device-specific constraints and eSCL request format. Add another profile only
/// after verifying its capabilities and actual image delivery on real hardware.
struct DS940Profile: ESCLScannerProfile {
  let name = "Brother DS-940DW"
  let resolutions = [300]
  func matchesService(_ name: String) -> Bool { name.localizedCaseInsensitiveContains("DS-940") }
  func matchesCapabilities(_ caps: ScanXML) -> Bool {
    caps.values["MakeAndModel"]?.contains(where: { $0.contains("DS-940") }) == true
  }
  func capabilities(from caps: ScanXML) -> ScannerCapabilities {
    // Keep simplex and duplex limits separate. This model advertises only 4200
    // units for duplex; its larger simplex limit must not leak into duplex jobs.
    let path = "ScannerCapabilities/Adf/AdfSimplexInputCaps/MaxHeight"
    let height = caps.paths[path]?.compactMap(Int.init).min() ?? 0
    return ScannerCapabilities(
      duplex: caps.values["AdfOption"]?.contains("Duplex") == true,
      resolutions: resolutions,
      paperModes: height >= 21600 ? [.standard, .longPaper] : [.standard])
  }
  func settings(options: ScanOptions) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
      <pwg:Version>2.0</pwg:Version><scan:Intent>Document</scan:Intent>
      <pwg:ScanRegions><pwg:ScanRegion><pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits><pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset><pwg:Width>2480</pwg:Width><pwg:Height>\(options.paperMode == .longPaper ? 21600 : 3508)</pwg:Height></pwg:ScanRegion></pwg:ScanRegions>
      <pwg:InputSource>Feeder</pwg:InputSource><scan:ColorMode>RGB24</scan:ColorMode><pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat><scan:DocumentFormatExt>image/jpeg</scan:DocumentFormatExt><scan:XResolution>300</scan:XResolution><scan:YResolution>300</scan:YResolution><scan:Duplex>\(options.duplex ? "true" : "false")</scan:Duplex>
      </scan:ScanSettings>
      """.utf8)
  }
}
