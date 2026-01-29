// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    productTypes: [
        // Build IssueReporting as static library to fix 'package' access visibility issue with Swift 6.2
        "IssueReporting": .staticLibrary,
        "IssueReportingPackageSupport": .staticLibrary,
        // Build AWS SDK modules as static libraries to properly link internal dependencies
        "AWSSDKIdentity": .staticLibrary,
        "AWSCloudWatch": .staticLibrary,
        "AWSSTS": .staticLibrary,
        "AWSPricing": .staticLibrary,
        "AWSSSO": .staticLibrary,
        "AWSSSOOIDC": .staticLibrary,
        // Internal AWS modules also need to be static libraries for proper linking
        "InternalAWSCognitoIdentity": .staticLibrary,
        "InternalAWSSTS": .staticLibrary,
        "InternalAWSSSO": .staticLibrary,
        "InternalAWSSSOOIDC": .staticLibrary,
        "InternalAWSSignin": .staticLibrary,
    ]
)
#endif

let package = Package(
    name: "ClaudeBar",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.1"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.6.43"),
    ]
)