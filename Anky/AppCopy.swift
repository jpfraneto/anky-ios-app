//
//  AppCopy.swift
//  Anky
//

import Foundation

enum AppCopyKey: String {
    case backupTitle
    case backupBody
    case backupLoseWarning
    case backupNoRecoveryWarning
    case backupNeverLeavesWarning
    case backupSavedAction
    case restorePhraseAction
    case restoreTitle
    case restoreBody
    case restorePlaceholder
    case restoreConfirmAction
    case restoreCancelAction
    case nowTab
    case ankysTab
    case seedTab
    case persistedAnkysTitle
    case noPersistedAnkysTitle
    case noPersistedAnkysBody
    case pendingSyncTitle
    case pendingSyncBody
    case seedIdentityTitle
    case walletLabel
    case backupStatusLabel
    case localIdentityLabel
    case backedUpValue
    case notBackedUpValue
    case rebootIdentityAction
    case rebootIdentityBody
    case identityReadyValue
    case identityMissingValue
    case openAnkysAction
}

struct AppCopy {
    private static let fallbackLanguageCode = "en"

    static var current: AppCopy {
        AppCopy(languageCode: resolvedLanguageCode())
    }

    let languageCode: String

    subscript(key: AppCopyKey) -> String {
        if let translation = Self.translations[languageCode]?[key] {
            return translation
        }

        return Self.translations[Self.fallbackLanguageCode]?[key] ?? key.rawValue
    }

    private static func resolvedLanguageCode() -> String {
        let preferred = Locale.preferredLanguages.first ?? fallbackLanguageCode
        let normalized = preferred.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init) ?? fallbackLanguageCode
    }

    private static let translations: [String: [AppCopyKey: String]] = [
        "en": [
            .backupTitle: "Your recovery phrase",
            .backupBody: "Write down these 24 words. They restore your writings.",
            .backupLoseWarning: "If you lose this phrase, you lose your writings forever.",
            .backupNoRecoveryWarning: "Anky cannot recover it for you.",
            .backupNeverLeavesWarning: "The phrase never leaves this device.",
            .backupSavedAction: "I saved it",
            .restorePhraseAction: "Restore phrase",
            .restoreTitle: "Restore with 24 words",
            .restoreBody: "Enter the phrase locally. Anky never sends it anywhere.",
            .restorePlaceholder: "24 words",
            .restoreConfirmAction: "Restore",
            .restoreCancelAction: "Back",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
            .persistedAnkysTitle: "Persisted ankys",
            .noPersistedAnkysTitle: "Nothing persisted yet",
            .noPersistedAnkysBody: "A real anky will appear here after it persists.",
            .pendingSyncTitle: "Waiting to persist",
            .pendingSyncBody: "This real anky is still local. It unlocks only after the backend persists it.",
            .seedIdentityTitle: "Seed identity",
            .walletLabel: "Wallet",
            .backupStatusLabel: "Backup",
            .localIdentityLabel: "Identity",
            .backedUpValue: "Backed up",
            .notBackedUpValue: "Not backed up",
            .rebootIdentityAction: "Reboot identity",
            .rebootIdentityBody: "Delete the local key, local drafts, and begin again with a new phrase.",
            .identityReadyValue: "Ready",
            .identityMissingValue: "Missing",
            .openAnkysAction: "Open ankys",
        ],
        "es": [
            .backupTitle: "Tu frase de recuperacion",
            .backupBody: "Escribe estas 24 palabras. Restauran tus escritos.",
            .backupLoseWarning: "Si pierdes esta frase, pierdes tus escritos para siempre.",
            .backupNoRecoveryWarning: "Anky no puede recuperarla por ti.",
            .backupNeverLeavesWarning: "La frase nunca sale de este dispositivo.",
            .backupSavedAction: "Ya la guarde",
            .restorePhraseAction: "Restaurar frase",
            .restoreTitle: "Restaurar con 24 palabras",
            .restoreBody: "Ingresa la frase localmente. Anky nunca la envia.",
            .restorePlaceholder: "24 palabras",
            .restoreConfirmAction: "Restaurar",
            .restoreCancelAction: "Volver",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEMILLA",
        ],
        "pt": [
            .backupTitle: "Sua frase de recuperacao",
            .backupBody: "Anote estas 24 palavras. Elas restauram seus escritos.",
            .backupLoseWarning: "Se voce perder esta frase, perde seus escritos para sempre.",
            .backupNoRecoveryWarning: "A Anky nao pode recupera-la para voce.",
            .backupNeverLeavesWarning: "A frase nunca sai deste aparelho.",
            .backupSavedAction: "Ja guardei",
            .restorePhraseAction: "Restaurar frase",
            .restoreTitle: "Restaurar com 24 palavras",
            .restoreBody: "Digite a frase localmente. A Anky nunca a envia.",
            .restorePlaceholder: "24 palavras",
            .restoreConfirmAction: "Restaurar",
            .restoreCancelAction: "Voltar",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEMENTE",
        ],
        "fr": [
            .backupTitle: "Votre phrase de recuperation",
            .backupBody: "Notez ces 24 mots. Ils restaurent vos ecrits.",
            .backupLoseWarning: "Si vous perdez cette phrase, vous perdez vos ecrits pour toujours.",
            .backupNoRecoveryWarning: "Anky ne peut pas la recuperer pour vous.",
            .backupNeverLeavesWarning: "La phrase ne quitte jamais cet appareil.",
            .backupSavedAction: "Je l'ai notee",
            .restorePhraseAction: "Restaurer la phrase",
            .restoreTitle: "Restaurer avec 24 mots",
            .restoreBody: "Entrez la phrase localement. Anky ne l'envoie jamais.",
            .restorePlaceholder: "24 mots",
            .restoreConfirmAction: "Restaurer",
            .restoreCancelAction: "Retour",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "GRAINE",
        ],
        "de": [
            .backupTitle: "Deine Wiederherstellungsphrase",
            .backupBody: "Schreibe diese 24 Worter auf. Sie stellen deine Texte wieder her.",
            .backupLoseWarning: "Wenn du diese Phrase verlierst, verlierst du deine Texte fur immer.",
            .backupNoRecoveryWarning: "Anky kann sie nicht fur dich wiederherstellen.",
            .backupNeverLeavesWarning: "Die Phrase verlasst dieses Gerat nie.",
            .backupSavedAction: "Ich habe sie notiert",
            .restorePhraseAction: "Phrase wiederherstellen",
            .restoreTitle: "Mit 24 Wortern wiederherstellen",
            .restoreBody: "Gib die Phrase lokal ein. Anky sendet sie nie weg.",
            .restorePlaceholder: "24 Worter",
            .restoreConfirmAction: "Wiederherstellen",
            .restoreCancelAction: "Zuruck",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "it": [
            .backupTitle: "La tua frase di recupero",
            .backupBody: "Scrivi queste 24 parole. Ripristinano i tuoi scritti.",
            .backupLoseWarning: "Se perdi questa frase, perdi i tuoi scritti per sempre.",
            .backupNoRecoveryWarning: "Anky non puo recuperarla per te.",
            .backupNeverLeavesWarning: "La frase non lascia mai questo dispositivo.",
            .backupSavedAction: "L'ho salvata",
            .restorePhraseAction: "Ripristina frase",
            .restoreTitle: "Ripristina con 24 parole",
            .restoreBody: "Inserisci la frase localmente. Anky non la invia mai.",
            .restorePlaceholder: "24 parole",
            .restoreConfirmAction: "Ripristina",
            .restoreCancelAction: "Indietro",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEME",
        ],
        "nl": [
            .backupTitle: "Je herstelzin",
            .backupBody: "Schrijf deze 24 woorden op. Ze herstellen je schrijfsels.",
            .backupLoseWarning: "Als je deze zin verliest, verlies je je schrijfsels voorgoed.",
            .backupNoRecoveryWarning: "Anky kan die niet voor je herstellen.",
            .backupNeverLeavesWarning: "De zin verlaat dit toestel nooit.",
            .backupSavedAction: "Ik heb hem bewaard",
            .restorePhraseAction: "Herstelzin invoeren",
            .restoreTitle: "Herstellen met 24 woorden",
            .restoreBody: "Voer de zin lokaal in. Anky verstuurt hem nooit.",
            .restorePlaceholder: "24 woorden",
            .restoreConfirmAction: "Herstellen",
            .restoreCancelAction: "Terug",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "ZAAD",
        ],
        "pl": [
            .backupTitle: "Twoja fraza odzyskiwania",
            .backupBody: "Zapisz te 24 slowa. Przywroca twoje pisma.",
            .backupLoseWarning: "Jesli zgubisz ta fraze, stracisz swoje pisma na zawsze.",
            .backupNoRecoveryWarning: "Anky nie moze jej odzyskac za ciebie.",
            .backupNeverLeavesWarning: "Fraza nigdy nie opuszcza tego urzadzenia.",
            .backupSavedAction: "Mam zapisane",
            .restorePhraseAction: "Przywroc fraze",
            .restoreTitle: "Przywroc z 24 slow",
            .restoreBody: "Wpisz fraze lokalnie. Anky nigdy jej nie wysyla.",
            .restorePlaceholder: "24 slowa",
            .restoreConfirmAction: "Przywroc",
            .restoreCancelAction: "Wroc",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "ZIARNO",
        ],
        "tr": [
            .backupTitle: "Kurtarma ifaden",
            .backupBody: "Bu 24 kelimeyi yaz. Yazilarini geri getirir.",
            .backupLoseWarning: "Bu ifadeyi kaybedersen yazilarini sonsuza kadar kaybedersin.",
            .backupNoRecoveryWarning: "Anky bunu senin icin geri getiremez.",
            .backupNeverLeavesWarning: "Ifade bu cihazdan asla cikmaz.",
            .backupSavedAction: "Kaydettim",
            .restorePhraseAction: "Ifadeyi geri yukle",
            .restoreTitle: "24 kelime ile geri yukle",
            .restoreBody: "Ifadeyi yerel olarak gir. Anky onu asla gondermez.",
            .restorePlaceholder: "24 kelime",
            .restoreConfirmAction: "Geri yukle",
            .restoreCancelAction: "Geri",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "TOHUM",
        ],
        "ru": [
            .backupTitle: "Vasha fraza vosstanovleniya",
            .backupBody: "Zapishite eti 24 slova. Oni vosstanovyat vashi teksty.",
            .backupLoseWarning: "Esli vy poteryaete etu frazu, vy poteryaete svoi teksty navsegda.",
            .backupNoRecoveryWarning: "Anky ne mozhet vosstanovit ee za vas.",
            .backupNeverLeavesWarning: "Fraza nikogda ne pokidaet eto ustroystvo.",
            .backupSavedAction: "Ya ee sokhranil",
            .restorePhraseAction: "Vosstanovit frazu",
            .restoreTitle: "Vosstanovit po 24 slovam",
            .restoreBody: "Vvedite frazu lokalno. Anky nikuda ee ne otpravlyaet.",
            .restorePlaceholder: "24 slova",
            .restoreConfirmAction: "Vosstanovit",
            .restoreCancelAction: "Nazad",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "ja": [
            .backupTitle: "回復フレーズ",
            .backupBody: "この24語を書き留めてください。あなたの書いたものを復元します。",
            .backupLoseWarning: "このフレーズを失うと、あなたの書いたものを永遠に失います。",
            .backupNoRecoveryWarning: "Anky はこれを復元できません。",
            .backupNeverLeavesWarning: "このフレーズは端末の外に出ません。",
            .backupSavedAction: "控えました",
            .restorePhraseAction: "フレーズを復元",
            .restoreTitle: "24語で復元",
            .restoreBody: "端末上でフレーズを入力してください。Anky は送信しません。",
            .restorePlaceholder: "24語",
            .restoreConfirmAction: "復元",
            .restoreCancelAction: "戻る",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "ko": [
            .backupTitle: "복구 문구",
            .backupBody: "이 24개 단어를 적어 두세요. 당신의 글을 복원합니다.",
            .backupLoseWarning: "이 문구를 잃으면 당신의 글을 영원히 잃습니다.",
            .backupNoRecoveryWarning: "Anky 는 이것을 복구할 수 없습니다.",
            .backupNeverLeavesWarning: "문구는 이 기기를 떠나지 않습니다.",
            .backupSavedAction: "저장했어요",
            .restorePhraseAction: "문구 복원",
            .restoreTitle: "24단어로 복원",
            .restoreBody: "문구를 기기에서 입력하세요. Anky 는 보내지 않습니다.",
            .restorePlaceholder: "24단어",
            .restoreConfirmAction: "복원",
            .restoreCancelAction: "뒤로",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "zh": [
            .backupTitle: "恢复短语",
            .backupBody: "请记下这24个词。它们可以恢复你的书写。",
            .backupLoseWarning: "如果你丢失这组短语，你将永远失去你的书写。",
            .backupNoRecoveryWarning: "Anky 无法替你恢复它。",
            .backupNeverLeavesWarning: "这组短语永远不会离开这台设备。",
            .backupSavedAction: "我已记下",
            .restorePhraseAction: "恢复短语",
            .restoreTitle: "用24个词恢复",
            .restoreBody: "请在本地输入短语。Anky 不会发送它。",
            .restorePlaceholder: "24个词",
            .restoreConfirmAction: "恢复",
            .restoreCancelAction: "返回",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "ar": [
            .backupTitle: "عبارة الاستعادة",
            .backupBody: "اكتب هذه الكلمات الاربع والعشرين. هي تستعيد كتاباتك.",
            .backupLoseWarning: "اذا فقدت هذه العبارة فستفقد كتاباتك الى الابد.",
            .backupNoRecoveryWarning: "لا تستطيع Anky استعادتها لك.",
            .backupNeverLeavesWarning: "العبارة لا تغادر هذا الجهاز ابدا.",
            .backupSavedAction: "لقد حفظتها",
            .restorePhraseAction: "استعادة العبارة",
            .restoreTitle: "استعادة ب 24 كلمة",
            .restoreBody: "ادخل العبارة محليا. Anky لا ترسلها الى اي مكان.",
            .restorePlaceholder: "24 كلمة",
            .restoreConfirmAction: "استعادة",
            .restoreCancelAction: "رجوع",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "hi": [
            .backupTitle: "रिकवरी वाक्यांश",
            .backupBody: "इन 24 शब्दों को लिख लें। ये आपकी लिखाइयों को वापस लाते हैं।",
            .backupLoseWarning: "अगर आप यह वाक्यांश खो देते हैं, तो आपकी लिखाइयां हमेशा के लिए खो जाएंगी।",
            .backupNoRecoveryWarning: "Anky इसे आपके लिए वापस नहीं ला सकता।",
            .backupNeverLeavesWarning: "यह वाक्यांश इस डिवाइस से बाहर नहीं जाता।",
            .backupSavedAction: "मैंने लिख लिया",
            .restorePhraseAction: "वाक्यांश बहाल करें",
            .restoreTitle: "24 शब्दों से बहाल करें",
            .restoreBody: "वाक्यांश यहीं दर्ज करें। Anky इसे कहीं नहीं भेजता।",
            .restorePlaceholder: "24 शब्द",
            .restoreConfirmAction: "बहाल करें",
            .restoreCancelAction: "वापस",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "SEED",
        ],
        "id": [
            .backupTitle: "Frasa pemulihanmu",
            .backupBody: "Tuliskan 24 kata ini. Kata-kata ini memulihkan tulisanmu.",
            .backupLoseWarning: "Jika kamu kehilangan frasa ini, kamu kehilangan tulisanmu selamanya.",
            .backupNoRecoveryWarning: "Anky tidak bisa memulihkannya untukmu.",
            .backupNeverLeavesWarning: "Frasa ini tidak pernah meninggalkan perangkat ini.",
            .backupSavedAction: "Sudah kusimpan",
            .restorePhraseAction: "Pulihkan frasa",
            .restoreTitle: "Pulihkan dengan 24 kata",
            .restoreBody: "Masukkan frasa secara lokal. Anky tidak pernah mengirimkannya.",
            .restorePlaceholder: "24 kata",
            .restoreConfirmAction: "Pulihkan",
            .restoreCancelAction: "Kembali",
            .nowTab: "NOW",
            .ankysTab: "ANKYS",
            .seedTab: "BENIH",
        ],
    ]
}
