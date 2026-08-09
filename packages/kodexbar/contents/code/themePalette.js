// KodexBar dual palette. The widget ships a custom dark design and does not
// inherit Plasma color roles directly. When the system theme is light, every
// custom color is swapped for a mirrored light equivalent so the same design
// stays legible. Dark mode is the identity: colors pass through untouched.
// Keys and values are hex strings without the leading "#".

var lightMap = {
    // Neutral surfaces, borders and lines
    "0a0c10": "aab1c2",
    "0b0c10": "d9dce6",
    "0f1015": "e4e7f0",
    "0f1116": "edeff6",
    "11141b": "e6e9f2",
    "12151c": "f2f4f9",
    "131419": "f6f7fb",
    "14161d": "ffffff",
    "171a22": "eef0f6",
    "171a23": "f0f2f8",
    "171920": "eceef5",
    "1a1d26": "e3e6ef",
    "1b1e28": "f1f3f8",
    "1c2029": "e9edf4",
    "20232b": "dadde7",
    "20232d": "e5e8f1",
    "22252f": "dde1ea",
    "242836": "dbe1ee",
    "262a35": "d2d7e2",
    "282b34": "cdd2de",
    "292c36": "d4d9e4",
    "2a2d37": "c9cfdb",
    "2b303c": "c6cdd9",
    "2f333d": "c2c8d5",
    "30333e": "bfc5d3",
    "303440": "bcc3d1",
    "303441": "f8f9fc",
    "333844": "b6bdcc",
    "33384d": "b1b8cb",
    "333a4c": "acb4c7",
    "343943": "b3bac9",
    "3a3f4d": "a6adbf",
    // Accent-tinted surfaces
    "1c1929": "e8e5f7",
    "1c1a29": "e5e2f5",
    "201d2d": "e6e3f6",
    "211d31": "e4e1f5",
    "211d3d": "e2def4",
    "242035": "dfdbf3",
    "29233e": "dcd7f2",
    "292343": "dcd8f2",
    "29243d": "ddd9f2",
    "29244e": "d8d3f0",
    "29253b": "e1ddf4",
    "413b71": "c9c3e8",
    // Accent purples, darkened to keep contrast on light surfaces
    "6e5aff": "5b46e0",
    "7a67ff": "6a52f0",
    "5543d8": "4a38c2",
    "8f72ff": "7b5bf2",
    "a98cff": "805af0",
    "9475ed": "7a50e8",
    "9b7cff": "7b57ee",
    "a898ff": "835ef2",
    "b4a5ff": "8668f0",
    "9787ff": "7d61ec",
    "cbbfff": "6a4fe0",
    "8064d8": "7350d6",
    "8f7bff": "7a58ee",
    "7c5cff": "6a45e8",
    // Status and category colors
    "45d483": "1d9d55",
    "f0b429": "a97c0a",
    "f76b6b": "d33f3f",
    "ffd166": "b98900",
    "5ac8fa": "0c8dc7",
    "22c7e8": "0d94bb",
    "ff5ebe": "d63a9c",
    "2b2027": "fbecec",
    "6b3943": "e2b7bc",
    "ff8888": "c24040",
    "cc9999": "9c5f5f",
    "d5a7ad": "a35660",
    "111b19": "e4f3ea",
    "1d171c": "f8ebeb",
    // Text and icon tones
    "e9ebf2": "1b1e29",
    "f2f3f8": "12141d",
    "c3c7d2": "484f63",
    "8b91a3": "5a6175",
    "7a8093": "5e6577",
    "6b7080": "6e7487",
    "565b68": "7b8193",
    "e7e9ef": "dfe2ec"
}

function isDarkColor(colorValue) {
    var lum = 0.2126 * colorValue.r + 0.7152 * colorValue.g + 0.0722 * colorValue.b
    return lum < 0.5
}

function lightEquivalent(hexColor) {
    var key = String(hexColor).replace("#", "").toLowerCase()
    if (Object.prototype.hasOwnProperty.call(lightMap, key)) {
        return "#" + lightMap[key]
    }
    return hexColor
}

function themed(hexColor, darkMode) {
    return darkMode ? hexColor : lightEquivalent(hexColor)
}
