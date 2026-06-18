function transliterate(text) {
    if (!text) return "";
    
    // Check if the text contains any native scripts (Devanagari: \u0900-\u097F, Gurmukhi: \u0A00-\u0A7F)
    const nativeRegex = /[\u0900-\u097F\u0A00-\u0A7F]/;
    if (!nativeRegex.test(text)) return text;

    // Normalize nuqta variants before processing
    text = text.replace(/\u0915\u093C/g, '\u0958')
               .replace(/\u0916\u093C/g, '\u0959')
               .replace(/\u0917\u093C/g, '\u095A')
               .replace(/\u091C\u093C/g, '\u095B')
               .replace(/\u0921\u093C/g, '\u095C')
               .replace(/\u0922\u093C/g, '\u095D')
               .replace(/\u092B\u093C/g, '\u095E')
               .replace(/\u092F\u093C/g, '\u095F')
               .replace(/[\u093C\u0A3C]/g, '');

    const dewaMap = {
        '\u0905': 'a', '\u0906': 'aa', '\u0907': 'i', '\u0908': 'ee', '\u0909': 'u', '\u090A': 'oo', '\u090B': 'ri', '\u090F': 'e', '\u0910': 'ai', '\u0913': 'o', '\u0914': 'au',
        '\u0915': 'k', '\u0916': 'kh', '\u0917': 'g', '\u0918': 'gh', '\u0919': 'n', '\u091A': 'ch', '\u091B': 'chh', '\u091C': 'j', '\u091D': 'jh', '\u091E': 'n',
        '\u091F': 't', '\u0920': 'th', '\u0921': 'd', '\u0922': 'dh', '\u0923': 'n', '\u0924': 't', '\u0925': 'th', '\u0926': 'd', '\u0927': 'dh', '\u0928': 'n',
        '\u092A': 'p', '\u092B': 'ph', '\u092C': 'b', '\u092D': 'bh', '\u092E': 'm', '\u092F': 'y', '\u0930': 'r', '\u0932': 'l', '\u0933': 'l', '\u0935': 'v', '\u0936': 'sh', '\u0937': 'sh', '\u0938': 's', '\u0939': 'h',
        '\u093E': 'aa', '\u093F': 'i', '\u0940': 'ee', '\u0941': 'u', '\u0942': 'oo', '\u0943': 'ri', '\u0947': 'e', '\u0948': 'ai', '\u094B': 'o', '\u094C': 'au',
        '\u0901': 'n', '\u0902': 'n', '\u0903': 'h', '\u094D': '', '\u0958': 'q', '\u0959': 'kh', '\u095A': 'g', '\u095B': 'z', '\u095C': 'r', '\u095D': 'rh', '\u095E': 'f', '\u095F': 'y'
    };

    const gurMap = {
        '\u0A05': 'a', '\u0A06': 'aa', '\u0A07': 'i', '\u0A08': 'ee', '\u0A09': 'u', '\u0A0A': 'oo', '\u0A0F': 'e', '\u0A10': 'ai', '\u0A13': 'o', '\u0A14': 'au',
        '\u0A15': 'k', '\u0A16': 'kh', '\u0A17': 'g', '\u0A18': 'gh', '\u0A1A': 'ch', '\u0A1B': 'chh', '\u0A1C': 'j', '\u0A1D': 'jh',
        '\u0A1F': 't', '\u0A20': 'th', '\u0A21': 'd', '\u0A22': 'dh', '\u0A23': 'n', '\u0A24': 't', '\u0A25': 'th', '\u0A26': 'd', '\u0A27': 'dh', '\u0A28': 'n',
        '\u0A2A': 'p', '\u0A2B': 'ph', '\u0A2C': 'b', '\u0A2D': 'bh', '\u0A2E': 'm', '\u0A2F': 'y', '\u0A30': 'r', '\u0A32': 'l', '\u0A33': 'l', '\u0A35': 'v', '\u0A36': 'sh', '\u0A38': 's', '\u0A39': 'h',
        '\u0A3E': 'aa', '\u0A3F': 'i', '\u0A40': 'ee', '\u0A41': 'u', '\u0A42': 'oo', '\u0A47': 'e', '\u0A48': 'ai', '\u0A4B': 'o', '\u0A4C': 'au',
        '\u0A02': 'n', '\u0A70': 'n', '\u0A71': '', '\u0A4D': ''
    };

    const isConsonant = (c) => (c >= '\u0915' && c <= '\u0939') || (c >= '\u0958' && c <= '\u095F') || (c >= '\u0A15' && c <= '\u0A39');
    const isVowelSign = (c) => (c >= '\u093E' && c <= '\u094C') || (c >= '\u0A3E' && c <= '\u0A4C');
    
    let result = "";
    for (let i = 0; i < text.length; i++) {
        let char = text[i];
        let nextChar = text[i + 1];
        
        let mapped = dewaMap[char] !== undefined ? dewaMap[char] : gurMap[char];
        
        if (mapped !== undefined) {
            result += mapped;
            
            // Implicit 'a'
            if (isConsonant(char)) {
                let hasVowelOrVirama = false;
                if (nextChar) {
                    if (isVowelSign(nextChar) || nextChar === '\u094D' || nextChar === '\u0A4D') {
                        hasVowelOrVirama = true;
                    }
                }
                
                if (!hasVowelOrVirama) {
                    // Schwa deletion logic:
                    // Drop 'a' at the end of a word, or before a punctuation, or at the end of a string
                    // Drop 'a' if next character is a space
                    let isEndOfWord = !nextChar || nextChar === ' ' || nextChar === '\n' || nextChar === '\r' || /[\[\]\(\)\.,:;!?\-]/.test(nextChar);
                    
                    if (!isEndOfWord) {
                        result += 'a';
                    }
                }
            }
        } else {
            result += char;
        }
    }
    
    // Capitalize first letter of each line, excluding timestamp brackets
    let lines = result.split('\n');
    let finalLines = lines.map(line => {
        // Strip any remaining non-ASCII diacritics that might have leaked through
        let clean = line.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
        return clean.replace(/^(\[[^\]]+\]\s*)*([a-z])/, (match, p1, p2) => {
            return (p1 || '') + p2.toUpperCase();
        });
    });
    
    return finalLines.join('\n');
}

function parseLrc(text, romanize = true) {
    if (!text) return [];
    
    // Apply transliteration to the entire block first if enabled
    if (romanize) {
        text = transliterate(text);
    }
    
    let lines = text.split("\n");
    let result = [];

    let timeRegex = /\[(\d+):(\d+\.\d+|\d+)\]/g;

    // Blacklist for credits/metadata often found in NetEase lyrics
    const creditKeywords = [
        "作词", "作曲", "编曲", "制作", "收录", "演奏", "词：", "曲：", "Lyricist", "Composer", "Arranger", "Producer", "Mixing", "Mastering"
    ];

    for (let line of lines) {

        timeRegex.lastIndex = 0;
        let matches = [];
        let match;

        while ((match = timeRegex.exec(line)) !== null) {
            matches.push(match);
        }

    if (matches.length === 0) {
        // If no timestamps found, treat as plain lyrics
        result.push({
            time: -1,
            text: line.trim()
        });
        continue;
    }

        let lyric = line.replace(timeRegex, "").trim();

        let min = parseInt(matches[0][1]);
        let sec = parseFloat(matches[0][2]);
        let totalTime = min * 60 + sec;

        // Only filter credits if they appear in the first 20 seconds
        if (totalTime < 20) {
            let isCreditFormat = creditKeywords.some(k => lyric.includes(k));
            if (isCreditFormat && (lyric.includes(":") || lyric.includes("：") || lyric.length < 25)) {
                continue;
            }
        }

        for (let match of matches) {
            let min = parseInt(match[1]);
            let sec = parseFloat(match[2]);

            result.push({
                time: min * 60 + sec,
                text: lyric
            });
        }
    }

    result.sort((a, b) => a.time - b.time);
    return result;
}

function getCurrentLine(lyrics, position) {
    const epsilon = 0.1; // 100ms tolerance
    for (let i = lyrics.length - 1; i >= 0; i--) {
        if ((position + epsilon) >= lyrics[i].time) {
            return i;
        }
    }
    return -1;
}
