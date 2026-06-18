function transliterate(text) {
    if (!text) return "";

    const nativeRegex = /[\u0900-\u0D7F]/;
    if (!nativeRegex.test(text)) return text;

    text = text.replace(/\u0915\u093C/g, '\u0958')
        .replace(/\u0916\u093C/g, '\u0959')
        .replace(/\u0917\u093C/g, '\u095A')
        .replace(/\u091C\u093C/g, '\u095B')
        .replace(/\u0921\u093C/g, '\u095C')
        .replace(/\u0922\u093C/g, '\u095D')
        .replace(/\u092B\u093C/g, '\u095E')
        .replace(/\u092F\u093C/g, '\u095F')
        .replace(/[\u093C\u0A3C]/g, '');

    const scripts = [
        {
            start: 0x0900,
            virama: '\u094D',
            consonants: {
                '\u0915': 'k', '\u0916': 'kh', '\u0917': 'g', '\u0918': 'gh', '\u0919': 'ng', '\u091A': 'ch', '\u091B': 'chh', '\u091C': 'j', '\u091D': 'jh', '\u091E': 'ny',
                '\u091F': 't', '\u0920': 'th', '\u0921': 'd', '\u0922': 'dh', '\u0923': 'n', '\u0924': 't', '\u0925': 'th', '\u0926': 'd', '\u0927': 'dh', '\u0928': 'n',
                '\u092A': 'p', '\u092B': 'ph', '\u092C': 'b', '\u092D': 'bh', '\u092E': 'm', '\u092F': 'y', '\u0930': 'r', '\u0932': 'l', '\u0933': 'l', '\u0935': 'v', '\u0936': 'sh', '\u0937': 'sh', '\u0938': 's', '\u0939': 'h',
                '\u0958': 'q', '\u0959': 'kh', '\u095A': 'gh', '\u095B': 'z', '\u095C': 'r', '\u095D': 'rh', '\u095E': 'f', '\u095F': 'y'
            },
            vowels: {
                '\u0905': 'a', '\u0906': 'aa', '\u0907': 'i', '\u0908': 'ee', '\u0909': 'u', '\u090A': 'oo', '\u090B': 'ri', '\u090F': 'e', '\u0910': 'ai', '\u0913': 'o', '\u0914': 'au'
            },
            marks: {
                '\u093E': 'aa', '\u093F': 'i', '\u0940': 'ee', '\u0941': 'u', '\u0942': 'oo', '\u0943': 'ri', '\u0947': 'e', '\u0948': 'ai', '\u094B': 'o', '\u094C': 'au', '\u0901': 'n', '\u0902': 'n', '\u0903': 'h'
            },
            dropFinalSchwa: true
        },
        {
            start: 0x0A00,
            virama: '\u0A4D',
            consonants: {
                '\u0A15': 'k', '\u0A16': 'kh', '\u0A17': 'g', '\u0A18': 'gh', '\u0A1A': 'ch', '\u0A1B': 'chh', '\u0A1C': 'j', '\u0A1D': 'jh',
                '\u0A1F': 't', '\u0A20': 'th', '\u0A21': 'd', '\u0A22': 'dh', '\u0A23': 'n', '\u0A24': 't', '\u0A25': 'th', '\u0A26': 'd', '\u0A27': 'dh', '\u0A28': 'n',
                '\u0A2A': 'p', '\u0A2B': 'ph', '\u0A2C': 'b', '\u0A2D': 'bh', '\u0A2E': 'm', '\u0A2F': 'y', '\u0A30': 'r', '\u0A32': 'l', '\u0A33': 'l', '\u0A35': 'v', '\u0A36': 'sh', '\u0A38': 's', '\u0A39': 'h'
            },
            vowels: { '\u0A05': 'a', '\u0A06': 'aa', '\u0A07': 'i', '\u0A08': 'ee', '\u0A09': 'u', '\u0A0A': 'oo', '\u0A0F': 'e', '\u0A10': 'ai', '\u0A13': 'o', '\u0A14': 'au' },
            marks: { '\u0A3E': 'aa', '\u0A3F': 'i', '\u0A40': 'ee', '\u0A41': 'u', '\u0A42': 'oo', '\u0A47': 'e', '\u0A48': 'ai', '\u0A4B': 'o', '\u0A4C': 'au', '\u0A02': 'n', '\u0A70': 'n', '\u0A71': '' },
            dropFinalSchwa: true
        },
        {
            start: 0x0980,
            virama: '\u09CD',
            consonants: { '\u0995': 'k', '\u0996': 'kh', '\u0997': 'g', '\u0998': 'gh', '\u0999': 'ng', '\u099A': 'ch', '\u099B': 'chh', '\u099C': 'j', '\u099D': 'jh', '\u099E': 'ny', '\u099F': 't', '\u09A0': 'th', '\u09A1': 'd', '\u09A2': 'dh', '\u09A3': 'n', '\u09A4': 't', '\u09A5': 'th', '\u09A6': 'd', '\u09A7': 'dh', '\u09A8': 'n', '\u09AA': 'p', '\u09AB': 'ph', '\u09AC': 'b', '\u09AD': 'bh', '\u09AE': 'm', '\u09AF': 'y', '\u09B0': 'r', '\u09B2': 'l', '\u09B6': 'sh', '\u09B7': 'sh', '\u09B8': 's', '\u09B9': 'h', '\u09DC': 'r', '\u09DD': 'rh', '\u09DF': 'y' },
            vowels: { '\u0985': 'a', '\u0986': 'aa', '\u0987': 'i', '\u0988': 'ee', '\u0989': 'u', '\u098A': 'oo', '\u098F': 'e', '\u0990': 'oi', '\u0993': 'o', '\u0994': 'ou' },
            marks: { '\u09BE': 'aa', '\u09BF': 'i', '\u09C0': 'ee', '\u09C1': 'u', '\u09C2': 'oo', '\u09C7': 'e', '\u09C8': 'oi', '\u09CB': 'o', '\u09CC': 'ou', '\u0981': 'n', '\u0982': 'n', '\u0983': 'h' },
            dropFinalSchwa: true
        },
        {
            start: 0x0A80,
            virama: '\u0ACD',
            consonants: { '\u0A95': 'k', '\u0A96': 'kh', '\u0A97': 'g', '\u0A98': 'gh', '\u0A99': 'ng', '\u0A9A': 'ch', '\u0A9B': 'chh', '\u0A9C': 'j', '\u0A9D': 'jh', '\u0A9E': 'ny', '\u0A9F': 't', '\u0AA0': 'th', '\u0AA1': 'd', '\u0AA2': 'dh', '\u0AA3': 'n', '\u0AA4': 't', '\u0AA5': 'th', '\u0AA6': 'd', '\u0AA7': 'dh', '\u0AA8': 'n', '\u0AAA': 'p', '\u0AAB': 'ph', '\u0AAC': 'b', '\u0AAD': 'bh', '\u0AAE': 'm', '\u0AAF': 'y', '\u0AB0': 'r', '\u0AB2': 'l', '\u0AB3': 'l', '\u0AB5': 'v', '\u0AB6': 'sh', '\u0AB7': 'sh', '\u0AB8': 's', '\u0AB9': 'h' },
            vowels: { '\u0A85': 'a', '\u0A86': 'aa', '\u0A87': 'i', '\u0A88': 'ee', '\u0A89': 'u', '\u0A8A': 'oo', '\u0A8B': 'ri', '\u0A8F': 'e', '\u0A90': 'ai', '\u0A93': 'o', '\u0A94': 'au' },
            marks: { '\u0ABE': 'aa', '\u0ABF': 'i', '\u0AC0': 'ee', '\u0AC1': 'u', '\u0AC2': 'oo', '\u0AC3': 'ri', '\u0AC7': 'e', '\u0AC8': 'ai', '\u0ACB': 'o', '\u0ACC': 'au', '\u0A81': 'n', '\u0A82': 'n', '\u0A83': 'h' },
            dropFinalSchwa: true
        },
        {
            start: 0x0B80,
            virama: '\u0BCD',
            consonants: { '\u0B95': 'k', '\u0B99': 'ng', '\u0B9A': 'ch', '\u0B9C': 'j', '\u0B9E': 'ny', '\u0B9F': 't', '\u0BA3': 'n', '\u0BA4': 'th', '\u0BA8': 'n', '\u0BA9': 'n', '\u0BAA': 'p', '\u0BAE': 'm', '\u0BAF': 'y', '\u0BB0': 'r', '\u0BB1': 'r', '\u0BB2': 'l', '\u0BB3': 'l', '\u0BB4': 'zh', '\u0BB5': 'v', '\u0BB6': 'sh', '\u0BB7': 'sh', '\u0BB8': 's', '\u0BB9': 'h' },
            vowels: { '\u0B85': 'a', '\u0B86': 'aa', '\u0B87': 'i', '\u0B88': 'ee', '\u0B89': 'u', '\u0B8A': 'oo', '\u0B8E': 'e', '\u0B8F': 'e', '\u0B90': 'ai', '\u0B92': 'o', '\u0B93': 'o', '\u0B94': 'au' },
            marks: { '\u0BBE': 'aa', '\u0BBF': 'i', '\u0BC0': 'ee', '\u0BC1': 'u', '\u0BC2': 'oo', '\u0BC6': 'e', '\u0BC7': 'e', '\u0BC8': 'ai', '\u0BCA': 'o', '\u0BCB': 'o', '\u0BCC': 'au', '\u0B82': 'n', '\u0B83': 'h' },
            dropFinalSchwa: false
        }
    ];

    function scriptFor(char) {
        const code = char.charCodeAt(0);
        return scripts.find(s => code >= s.start && code <= s.start + 0x7f);
    }

    function isWordEnd(nextChar) {
        return !nextChar || nextChar === ' ' || nextChar === '\n' || nextChar === '\r' || /[\[\]\(\)\.,:;!?\-]/.test(nextChar);
    }

    let result = "";
    for (let i = 0; i < text.length; i++) {
        const char = text[i];
        const nextChar = text[i + 1];
        const script = scriptFor(char);

        if (!script) {
            result += char;
            continue;
        }

        if (script.vowels[char] !== undefined) {
            result += script.vowels[char];
            continue;
        }

        if (script.marks[char] !== undefined) {
            result += script.marks[char];
            continue;
        }

        if (char === script.virama) {
            continue;
        }

        if (script.consonants[char] !== undefined) {
            result += script.consonants[char];
            const nextIsMark = nextChar && (script.marks[nextChar] !== undefined || nextChar === script.virama);
            if (!nextIsMark && (!script.dropFinalSchwa || !isWordEnd(nextChar))) {
                result += 'a';
            }
            continue;
        }

        result += char;
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
