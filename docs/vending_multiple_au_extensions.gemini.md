$ gemini -p "Point me to web pages that explain how to build an iOS app that hosts and registers multiple Audio Unit Extension. I'm only interested in the case where the app wants to offer more than one audio unit to other apps."
I will search for web pages and documentation that explain how to host and register multiple Audio Unit extensions within a single iOS application.
I will perform a more specific search to determine if multiple Audio Units can be registered within a single extension target using the `AudioComponents` array in the `Info.plist`.
I'll search for code examples and tutorials that demonstrate how to implement an `AUAudioUnitFactory` to handle the instantiation of multiple Audio Units based on their component descriptions.
To build an iOS app that hosts and registers multiple Audio Unit (AUv3) extensions within a single bundle, you need to configure your extension's `Info.plist` and implement a factory class to handle multiple subtypes.

Below are the key resources and an explanation of the architecture required for this setup.

### Key Documentation and Articles

1.  **Apple Developer Documentation: `AUAudioUnitFactory`**  
    This is the primary protocol your principal class must implement. It explains how the system requests an instance of your audio unit.  
    [developer.apple.com/documentation/audiotoolbox/auaudiounitfactory](https://developer.apple.com/documentation/audiotoolbox/auaudiounitfactory)

2.  **Apple Developer Documentation: Audio Unit V3 App Extension**  
    General overview of AUv3 extensions, though you must look specifically at the `AudioComponents` array section for multiple units.  
    [developer.apple.com/documentation/audiotoolbox/audio_unit_v3_app_extension](https://developer.apple.com/documentation/audiotoolbox/audio_unit_v3_app_extension)

3.  **AudioKit Pro: AUv3 Tutorials**  
    AudioKit provides extensive tutorials on AUv3. While many focus on single units, their architecture (using a factory) is designed to scale to multiple units.  
    [audiokitpro.com/auv3-tutorial-part-1/](https://audiokitpro.com/auv3-tutorial-part-1/)

### Core Implementation Strategy

To offer multiple audio units from one app extension, follow these two steps:

#### 1. Define Multiple Components in `Info.plist`
In your Audio Unit Extension's `Info.plist`, locate the `NSExtensionAttributes` dictionary. Instead of a single set of keys, use the `AudioComponents` key as an array of dictionaries. Each dictionary defines a unique Audio Unit:

```xml
<key>NSExtensionAttributes</key>
<dict>
    <key>AudioComponents</key>
    <array>
        <dict>
            <key>name</key>
            <string>MyCompany: Filter Effect</string>
            <key>type</key>
            <string>aufx</string>
            <key>subtype</key>
            <string>filt</string>
            <key>manufacturer</key>
            <string>myco</string>
            <!-- ... other keys ... -->
        </dict>
        <dict>
            <key>name</key>
            <string>MyCompany: Distortion Effect</string>
            <key>type</key>
            <string>aufx</string>
            <key>subtype</key>
            <string>dist</string>
            <key>manufacturer</key>
            <string>myco</string>
            <!-- ... other keys ... -->
        </dict>
    </array>
</dict>
```

#### 2. Implement the Factory Logic
Your `NSExtensionPrincipalClass` (the factory) receives the `AudioComponentDescription` when the host app attempts to instantiate a unit. Use the `componentSubType` to decide which subclass to return:

```swift
class MyAudioUnitFactory: NSObject, AUAudioUnitFactory {
    func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        switch componentDescription.componentSubType {
        case "filt".fourCharCode:
            return try MyFilterAudioUnit(componentDescription: componentDescription)
        case "dist".fourCharCode:
            return try MyDistortionAudioUnit(componentDescription: componentDescription)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported), userInfo: nil)
        }
    }
}
```

### Additional Tips
*   **Unique Subtypes:** Ensure every audio unit you register has a unique `subtype` four-character code.
*   **Shared Code:** Since all units reside in the same extension process, they can share the same binary code and resources, reducing the overall footprint of your app.
*   **UI/View Controllers:** If your units have different UIs, your `AUAudioUnit` subclasses should return the appropriate `AUViewController` in their `requestViewController` method.
