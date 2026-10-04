import CryptoKit
import Foundation

/// Wallets that live in a browser profile: the vaults of wallet extensions, and Brave's own wallet. A profile that
/// holds one stays whole, and so does a folder that holds it a level or two down, because an extension can also
/// keep its data in the profile's `Local Storage`, which every site and extension share.
///
/// The lists hold the SHA-256 of each extension's ID, never the ID itself. XProtect, the malware scanner built into
/// macOS, knows a program that steals wallets by the extension IDs it carries, and it moves a binary holding a few
/// of them to the Trash whatever the program does with them (rule `MACOS.SOMA.D` in `XProtect.yara`). Each ID
/// stays readable in the comment above its fingerprint, which the compiler leaves out of the binary.
extension ProtectedData {
    /// The fingerprints of wallet extensions for Chromium browsers, such as Chrome, Brave, Edge, Arc, Opera, and
    /// Vivaldi, from their listings in the Chrome Web Store and in Edge Add-ons. A listing marked withdrawn is no
    /// longer served, and an old install can still hold a vault. An ID belongs to one extension, so it matches
    /// nothing else.
    public static let walletExtensions: Set<String> = [
        // Alby: iokeahhehimjnekafflcihljlcjccdbe
        "54335d136c3d52a7849063542b96b45dde56122a8ea028db0496ccd01ceeabd1",
        // Ambire: ehgjhhccekdedpbkifaojjaefeohnoea
        "52c67f71f65000b71ceecf73a606e508a2dbec8cfd324248a62906a83b4dce1c",
        // Atomic Wallet: gjnckgkfmgmibbkoficdidcljeaaaheg
        "839eb8389682c393b840d30a1025e05f2bb59c87f6abf77120047b50cfe5c123",
        // Backpack: aflkmfhebedbjioipglgcbcmnbpgliof
        "e7f6bfb66b568de853c5f0bad9ec33f9c68bc6d3bdcb412fd46e199ee235eded",
        // Binance Chain Wallet, withdrawn: fhbohimaelbohpjbbldcngcnapndodjp
        "05cf49b3dcc0c900cc117a56dd6489e7804fa97c524319eafeaab36c48859a44",
        // Binance Wallet: cadiboklkpojfamcoggejbbdjcoiljjk
        "7b233a451838ef932122ea9cf062367ffe6b2d7814ce6a70477e8fe4f39048c2",
        // Bitget Wallet: jiidiaalihmmhddjgbnbgdfflelocpak
        "4a163d959b4d8b8692742d31ecab371adcd2fd560329b56ecb8b9126906589af",
        // Braavos: jnlgamecbpmbajjfhmmmlhejkemejdma
        "7301cec1871fe9f59326a0c0bac0129e5923a14424985d2c42820d09a4109bbd",
        // Bybit Wallet: pdliaogehgdbhbnmkklieghmmjkpigpa
        "ea3f956b26a1dfc1d5f2967b9272e0909c1549eda76ff4acdd836ee8c6824e8d",
        // Coin98: aeachknmefphepccionboohckonoeemg
        "49a935e40e34638e94c6ac9205b456a22801d9df6f99947545a2a45300da2d93",
        // Coin98, from Edge Add-ons, withdrawn: noonkmflgdnoeoelnnhaaphcnoopknig
        "92bf9a85f16553f1ed9c50ed4249edd0df7a055b8c1527cd93d8c2c606ad6fec",
        // Coinbase Wallet: hnfanknocfeofbddgcijnmhnfnkdnaad
        "e139dacc4ebc09c23a854fc51bb619e4bd163a777a08481a0c1b05ef22a2044e",
        // Coinbase Wallet, from Edge Add-ons, withdrawn: cclgcajjfhcakmjedohnccgmhdddkpfh
        "0a4ee58131c21e14191c48006ef875ecf82ed96c8889c8081d5c2c95699d101d",
        // Core: agoakfejjabomempkjlepdflaleeobhb
        "b0fd706049951b5f8845d34db4957f8b0f3d64be6a9061762f955bfe92a4ff83",
        // Cosmostation: fpkhgmpbidmiogeglndfbkegfdlnajnf
        "6c78c1b72ce51bb62a80a8c8becafcfab0f9c0732cc4407666a4a837a4837f8f",
        // Crypto.com Onchain: hifafgmccdpekplomjjkcfgodnhcellj
        "1c9163189e844d98a382b1a1c315193f067545c9e08f0b01faa5fef28bff510e",
        // Crypto.com, from Edge Add-ons, withdrawn: gpbdhlngfkgihnfeekcmkbbalpdflgmg
        "b981a4075640ef8b2fe365b704725ec219b22076f8de5d2e29011d1d38a7ea57",
        // Ctrl Wallet, formerly XDEFI: hmeobnfnfcmdkdcmlblgagmfpfboieaf
        "1e49f207d3e2ba1975c15454b1b1e847d313c21eefd9e6473ccbfaabc0285495",
        // Enkrypt: kkpllkodjeloidieedojogacfhpaihoh
        "6ea11db7a23a08f6c0a27e4590b032ec3d9959d4abbabdec4c02c961b4a7fc36",
        // Enkrypt, from Edge Add-ons: gfenajajnjjmmdojhdjmnngomkhlnfjl
        "054490f28f0d3036f3c42583713cead8f95bc66258713fee918d61ef24afcaa0",
        // Eternl: kmhcihpebfmpgmihbkipmjlmmioameka
        "701beb8085df6d56114489a5763bb9a526f7ce0e05affaf444d42c8356182e16",
        // Exodus Web3 Wallet: aholpfdialjgjfhomihkjbmgjidlcdno
        "7f7a23670eb287564aabe14dbbda8f2a88f4c26310390ef7905198cb2512f787",
        // Guarda: hpglfhgfnhbgpjdenjgmdgoeiappafln
        "481c38331739261484b3812dfa7ce899b7d8d31b6e3ca3b29310d36b79bf3cdf",
        // HashPack: gjagmgiddbbciopjhllkdnddhcglnemk
        "b8f3784dd3405e46d254da4ef3443932264fb92b2c3f8af25f3fb0cb7e0e5a76",
        // Keplr: dmkamcknogkgcdfhhbddcghachkejeap
        "16060af3d5f73a20397cf2fbff94071adac10903d0973530265eb6ebc739af7d",
        // Keplr, from Edge Add-ons: ocodgmmffbkkeecmadcijjhkmeohinei
        "d45d90a757cafa9e567b03796bdd1f37cbac46d9ac80b3f0d0d73c660a431181",
        // Lace: gafhhkghbfjjkeiendhlofajokpaflmk
        "7ac5cdf8c0304d3669fc4716822be6cee0be9543374ffb7631ea0d8efbe80f54",
        // Leap Cosmos Wallet, withdrawn: fcfcfllfndlomdhbehjjcoimbgofdncg
        "da6d3fab11d6ad615ea2cc70ec2e35f98d1f54393089ce02f1e00422019420c5",
        // Leather: ldinpeekobnhjjdofggfgjlcehhmanlj
        "f395f05735f18cd7b7b630f8fa224a97d7371cf472ed71cb70c1d809a4d673b5",
        // Magic Eden: mkpegjkblkkefacfnmkajcjmabijhclg
        "4c34d6534d8712bb7d4e6046b33e573a3ef5419aaa117189a296de5a7fe71141",
        // Martian: efbglgofoippbgcjepnhiblaibcnclgk
        "da7333b15f7b18e139281d6a78f0d5c10003cfcaa7fe8cd10794d4edc69d9084",
        // MathWallet: afbcbjpbpfadlkmhmclhkeeodmamcflc
        "31497d3c5083cb3949f40f795e38268e4ec3a9d2999586c5abdafdfaeb36665a",
        // MathWallet, from Edge Add-ons: dfeccadlilpndjjohbjdblepmjeahlmm
        "4467198c8ffb192bb5782e730d8db7d312b923e5c70af089a3ed0e551897de9e",
        // MetaMask: nkbihfbeogaeaoehlefnkodbefgpgknn
        "236d1c2349dcbf080a5ee149888b545ecad6b43dc560360f06be2aac4069e5ce",
        // MetaMask Flask: ljfoeinjpaedjfecbmggjgodbgkmjkjk
        "9097564df3d3cbccb27493dcab7e48fa1d5b3c72c1a3d6d7a2f7d871250724ae",
        // MetaMask, from Edge Add-ons: ejbalbakoplchlghecdalmeeeajnimhm
        "6c77888d7a8eb5be815c4b44b8ad07bacd353042f92f4a9c5c53d8a3ac305650",
        // My Wallet, formerly MyTonWallet: fldfpgipfncgndfolcbkdeeknbbbnhcc
        "6f1d8db7106ded0b70b87c077e37186037c5d6aebfe3d5ff464fb173f869514f",
        // Nami: lpfcbjknijpeeillifnkikgncikgfhdo
        "98de2c74f85de4a080048b455947cbb19abb654af2d89a45024adbf5ac8d15a6",
        // Nightly: fiikommddbeccaoicoejoniammnalkfa
        "a1ecf6753a231f0b9f2e671dd3ff2cb3ca76f23338c9813b27250e58156f3f20",
        // OKX Wallet: mcohilncbfahbmgdjkbpemcciiolgcge
        "7ed4974fa52e80026ebdf8d199060189191be1c27191afd975f8d4c6cb25f9e4",
        // OKX Wallet, from Edge Add-ons: pbpjkcldjiffchgbbndmhojiacbgflha
        "f6aea63722848fd2e3c87d0a2c57a52087ce72ba7364fa88144e3c38532b78e9",
        // OneKey: jnmbobjmhlngoefaiojfljckilhhlhcj
        "473b973c463c34348e2fa430e6556d77f5429d51b5eb451ba2e7da10cca77a84",
        // OneKey, from Edge Add-ons: obffkkagpmohennipjokmpllocnlndac
        "939f0a09e05d3a6687c10e5a85e131a646f7d15fff11e5d3869fa243a9d3eab9",
        // OpenMask: penjlddjkjgpnkllboccdgccekpkcbin
        "b1bb27f08f466820bf5803c00876c29e304cbb07df784be0a69e14246a3585f2",
        // Petra: ejjladinnckdgjemekebdpeokbikhfci
        "3c5fc2147981d472e621602caaa6fa2afc8150b941d4444d033598862cf48011",
        // Phantom: bfnaelmomeimhlpmgjnjophhpkkoljpa
        "457bbba6087abd61ed26c6db18f9258fdcd508b3ad34481afef7a7d49ae44ea7",
        // Phantom, from Edge Add-ons, withdrawn: bmnkhaipfhdepcgopndfebkamdikcjhi
        "98af4c28e569362c23a1a0cf34dc35e137486ca3564b5279be53e914b99c8c26",
        // polkadot{.js}: mopnmbcafieddcagagdcbnhejhlodfdd
        "37c3731cf4d0ed4b632b1bb5219ce30043b49ae3f1c3abd3e39248d7616705ca",
        // Pontem: phkbamefinggmakgklpkljjmgibohnba
        "0194c07603a6c3bdc4ae274330384ffd7d5a8a5428b9ad1a4d36739d3a097435",
        // Rabby: acmacodkjbdgmoleebolmdjonilkdbch
        "fdbcc88c100d3fd0baf5888d6e69e9f60abb46ab9634d6b18682c1ca575654fa",
        // Rainbow: opfgelmcmbiajamepnmloijbpoleiama
        "58e9b16463ebc725fa06927bdbebe3a8aec5a87572c9105490688b8c9ed97e1d",
        // Ready, formerly Argent X: dlcobpjiigpikoobohmabehhmhfoodbb
        "c830d8ad731267cbe6e3fdd4dc718d18a8c6d03ba415c9ee60ce93e53b0ba264",
        // Ronin: fnjhmkhhmkbjkkabndcnnogagogbneec
        "82ea7fe5283acdb80b87e3346d7e39e1b06e0d0a61dcf261cdb37d670f9b4847",
        // Ronin, from Edge Add-ons: kjmoohlgokccodicjjfebfomlbljgfhk
        "81d1be83e1e517a7ddb28d2eaf03456f3917901aaea7de55fd0cb0f988f7c75b",
        // SafePal: lgmpcpglpngdoalbgeoldeajfclnhafa
        "cfadd0fb037e1a70ec5d887e8b55b8971ad79fafc9c69c51c189fd18eacd5c5c",
        // SafePal, from Edge Add-ons: apenkfbbpmhihehmihndmmcdanacolnh
        "7157f98ef4dcc2264bf4b1603893684b12094a50c23a7d28cbe3b816d0668a28",
        // SecondFi, formerly Yoroi: ffnbelfdoeiohenkjibnmadjiehjhajb
        "641b30f55c707fcd89fc18c4d8c8560a7f42386e639d4ea7f0fb0b8e21373c1f",
        // SecondFi, from Edge Add-ons: akoiaibnepcedcplijmiamnaigbepmcb
        "939fb6f2a67d5b988e7378988363ecd7a394fceec31056ed8151054bc981ea57",
        // Slush, formerly Sui Wallet: opcgpfmipidbgpenhmajoajpbobppdil
        "af9d4616d22d91d651492edbc0f3be6ad6e2c43b05dc62bcdb0384aad93c4ab8",
        // Solflare: bhhhlbepdkbapadjdnnojkbgioiodbic
        "e5e3d9c385dd6a06b1daa03fb0ca2f26d6bacd7179ff9c36e1309ce730b86477",
        // Station: aiifbnbfobpmeekipheeijimdpnlpgpp
        "b552892aa933e42bc5371c5aa4b4daded27936c043fcbba3b7e928c67cee7d8e",
        // SubWallet: onhogfjeacnfoofkfgppdlbmlmnplgbn
        "c5ba81d486db388298fc6df0f4610f26d7af75392a56b183e0f7ae3c7413fc67",
        // Taho: eajafomhmkipbjmfmhebemolkcicgfmd
        "a3a0c5cd9e728c950fbd2c704ed2f8bb7638c2fb88d574be4cd8b8b7741ee0eb",
        // Talisman: fijngjgcjhjmmpcmkeiomlglpeiijkld
        "24f4a0a541490aaefc23d8b667d9db8ad451cbd7dcbba00f2527b60a2613560c",
        // Temple: ookjlbkiijinhpmnjffcofjonbfbgaoc
        "7291b6bc431a43f4ee38b23cde4e074cd3784a9764e2318c51b20c4c53d75063",
        // TokenPocket: mfgccjchihfkkindfppnaooecgfneiii
        "5a994c3dcab5c805825cf0084b24a74cc785f7ab88fac9ff026cb4510bd3a1b1",
        // Tonkeeper: omaabbefbmiijedngplfjmnooppbclkk
        "8484221dfd00dfb0a5dccb0e035d5097e2752c4ff5ea1610e85313fb95b0b771",
        // TronLink: ibnejdfjmmkpcnlpebklmnkoeoihofec
        "0968fd7a8577f69abf6eff96cf02bd1652952230a0a883efc8b2b70af6d454fe",
        // TronLink, from Edge Add-ons: aheklkkgnmlknpgogcnhkbenfllfcfjb
        "fcd32be9e1fabba31a3d9f489750aab47fc3b19d47771039dad8cf3f395d5f97",
        // Trust Wallet: egjidjbpglichdcondbcbdnbeeppgdph
        "0c95ff4a29972e157119e75189d502b410884f50cbe6df1acb512ccd7b60ac9c",
        // Trust Wallet, from Edge Add-ons, withdrawn: cmoejppohfldenjbieahmemfkglcenlf
        "9f54a78f6c91801cc533e8e1969dd930d35dfb61ce406137b969f3a2fda1c4b7",
        // UniSat: ppbibelpcjmhbdihakflkdcoccbgbkpo
        "655aca5197f03a5672bd0f98b32b516e8e500a184890fbfea6cb59dfa9d92d82",
        // Uniswap: nnpmfplkfogfpmcngplhnbdnnilmcdcg
        "bd6fa2745786fd6b6a22c2bf931b8ccf6f9d0b0bad1b55d2b963620d4fa8387e",
        // Xverse: idnnbdplmphpflfnlkomgpfbpcgelopg
        "fc2500db4fed3fdcd31968aecbde501f8909abca65f9fcd2374f86e082778b53",
        // Zerion: klghhnkeealcohjjanjjdaeeggmfmlpl
        "e7f95a0be1ba297d9565edd2cc0558efd46857816cf6bef452ca021898c3357c",
    ]

    /// The fingerprints of wallet add-ons on addons.mozilla.org, of their IDs in lowercase. Firefox installs an
    /// add-on as `extensions/<ID>.xpi` in the profile, and removes its storage when the add-on is removed.
    public static let walletAddOns: Set<String> = [
        // Alby: extension@getalby.com
        "f758c0ade84f7a93d09cbe7c6d9c15532bc336d3cf15d52c56563f081c97228d",
        // Ambire: wallet@ambire.com
        "306d0fc0eeeb74b3d040c32d22fee199905e5df19d60b473d262e41e58ce451e",
        // Braavos: {a0c6ccfd-26a3-4df4-9729-aa036070ad29}
        "d536965e0833bc553d1bc1058a5b94583d8747d334c16888a5453938f2ae3693",
        // Enkrypt: {21a9e8ea-7aa4-4aae-923c-ec8211f2779c}
        "0332d3649de49795f7074fa19aeda4f8d8f677adf66c736163b757894a3eb544",
        // Keplr: keplr-extension@keplr.app
        "6b0f6babbb81790dd97b8ddff12ab787d8748b269a8a635b09167b65b196f565",
        // Lace: lace-wallet-ext@lace.io
        "a4c5e84beddb359fae28624885da033ecf192535d3616625cec897b65421faa2",
        // MetaMask: webextension@metamask.io
        "ce84733ead38daa7c822e11172031b90a8c1afa029e97b120202ff9d294a1c1f",
        // MetaMask Flask: webextension-flask@metamask.io
        "c1376eab47cb9e03a886e6c12b09f027eb8a78fb84c073a97c7ea85e92d5f0c6",
        // My Wallet, formerly MyTonWallet: {98fcdaee-2b58-4f71-8a3c-f0c66f24dede}
        "d75f165247ed9fee1470778d5cbd5c3a4d0f4c68c5bc17a52a71bf2b6267e32f",
        // Nightly: {76026700-1d2e-4c46-8454-198e27682104}
        "16b79069b9be67309856bc41364bf6fdca535ef9783fa01217fe835fd730169c",
        // Phantom: {7c42eea1-b3e4-4be4-a56f-82a5852b12dc}
        "268a02ec6c026f9119c539be095d9cf28afb4cd8e2cbaf11da769ab281b21071",
        // polkadot{.js}: {7e3ce1f0-15fb-4fb1-99c6-25774749ec6d}
        "4499712a3dc85e4906da18bfb25acec2a50df42bdf4d109f5d927d49938de256",
        // Rainbow: browserextension@rainbow.me
        "1802cfc84fa2aedd44ac7efbdfae6a0a5d128d149153fc01b2c031f3ceefe7be",
        // Ready, formerly Argent: {51e0c76c-7dbc-41ba-a45d-c579be84301b}
        "bc41d70d731d4e0335e6c577f30468c841fadf883d12cd64cda6e4d0847c75f3",
        // Ronin: ronin-wallet@axieinfinity.com
        "2907115e80c4db9c3e6258873e812aa9b2c1f5141a22d8ed10751f3cb0dd3656",
        // Solflare: {6d72262a-b243-4dc6-8f4f-be96c74e0a86}
        "6859225ddefd61629e37a034f1f27efd97a5971b1a69cd53879493f3ef63d745",
        // SubWallet: {8a3a53f5-7490-46d7-b91d-f8549bb8df05}
        "ce5b6d31d558ea31a6899edc5205708367302288afc0993e54b61d56da9e8c75",
        // Talisman: {f5727e03-b26c-41e0-95dd-7e315ff16410}
        "8201dbc6334f5e9831ac8f27475041288427265d18d59671949d31f212ee9d32",
        // Tonkeeper: wallet@tonkeeper.com
        "2316b22a464674a9a9c523d721924a20ae69f1af6c837bcae2d2e0eac31179b3",
        // Yoroi: {530f7c6c-6077-4703-8f71-cb368c663e35}
        "1cc2bbde8109ee93a06fb52a2364ef92ca454a2fde9999a78b965343d5fec627",
        // Zerion: master@zerion.io
        "f6c94dd6e7008bdd134f3df52a54a7a5d31f1a1ee2940dbeadfad54aa6f9f1dc",
    ]

    /// The SHA-256 of `id`, in lowercase hex, which is how the lists above hold each ID.
    static func fingerprint(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// True for a path at or inside a wallet extension's storage: `Local Extension Settings/<ID>` or an IndexedDB
    /// store of `chrome-extension_<ID>_0` in a Chromium profile, or `extensions/<ID>.xpi` in a Firefox profile.
    /// Expects the path's names in lowercase.
    static func isInsideAWalletExtension(_ names: [String]) -> Bool {
        zip(names, names.dropFirst()).contains { folder, name in isAWalletsStorage(name, in: folder) }
    }

    /// True for a folder that is, or holds a level or two down, a browser profile with a wallet in it, which is
    /// as deep as a browser keeps a profile (`Google/Chrome/Default`, `Firefox/Profiles/<name>`), and for a
    /// profile's `Local Extension Settings`, `IndexedDB`, or `extensions` holding a wallet's storage. Inside such
    /// a profile it is also true for what a wallet can share with other extensions: `Local Storage`, Firefox's
    /// `storage`, and `Preferences`, where Brave keeps its own wallet. It reads the disk, so it needs the path as
    /// spelled on disk.
    public static func holdsABrowserWallet(_ path: String) -> Bool {
        let components = PathComponents.of(path)
        if let profile = profile(sharedBy: components), isAProfileWithAWallet(profile) { return true }
        // Only a folder can be a profile or hold one.
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
        if isAProfileWithAWallet(path) { return true }

        let folder = components.last?.lowercased() ?? ""
        return entries(of: path).contains { child in
            if isAWalletsStorage(child.name.lowercased(), in: folder) { return true }
            guard !child.isAFile else { return false }
            let inside = path + "/" + child.name
            return isAProfileWithAWallet(inside)
                || entries(of: inside).contains { !$0.isAFile && isAProfileWithAWallet(inside + "/" + $0.name) }
        }
    }

    /// The names in `folder`, each with whether it is a regular file, which is no profile and holds none. The kind
    /// comes with the listing, so a folder of many files costs no call for each file.
    private static func entries(of folder: String) -> [(name: String, isAFile: Bool)] {
        let url = URL(filePath: folder, directoryHint: .isDirectory)
        let found =
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]))
            ?? []
        return found.map {
            ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true)
        }
    }

    /// True for `name`, inside a folder called `folder`, when it is a wallet extension's storage. Both lowercase.
    private static func isAWalletsStorage(_ name: String, in folder: String) -> Bool {
        switch folder {
        case "local extension settings":
            return name.count == 32 && walletExtensions.contains(fingerprint(name))
        case "indexeddb":
            // `chrome-extension_<ID>_0.indexeddb.leveldb` and `.indexeddb.blob`, or the folder of its own that the
            // SQLite store gives each origin, `chrome-extension_<ID>_0`.
            guard name.hasPrefix("chrome-extension_") else { return false }
            let rest = name.dropFirst("chrome-extension_".count)
            let port = rest.dropFirst(32)
            guard port == "_0" || port.hasPrefix("_0.indexeddb.") else { return false }
            return walletExtensions.contains(fingerprint(String(rest.prefix(32))))
        case "extensions":
            return name.hasSuffix(".xpi") && walletAddOns.contains(fingerprint(String(name.dropLast(".xpi".count))))
        default:
            return false
        }
    }

    /// True for a browser profile that holds a wallet: a wallet extension's storage, a wallet add-on, or Brave's own
    /// wallet in its `Preferences`.
    private static func isAProfileWithAWallet(_ profile: String) -> Bool {
        for folder in ["Local Extension Settings", "IndexedDB", "extensions"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: profile + "/" + folder)) ?? []
            if names.contains(where: { isAWalletsStorage($0.lowercased(), in: folder.lowercased()) }) { return true }
        }
        return holdsBravesWallet(profile + "/Preferences")
    }

    /// True when a profile's `Preferences` carries Brave's wallet, whose encrypted recovery phrase Brave keeps there
    /// as `brave.wallet.encrypted_mnemonic`. A file too big or not allowed to be read is not known to be without
    /// one, so it counts as one.
    private static func holdsBravesWallet(_ file: String) -> Bool {
        var info = stat()
        guard lstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        guard info.st_size <= 64 << 20, let contents = FileManager.default.contents(atPath: file) else { return true }
        return contents.range(of: Data(#""encrypted_mnemonic""#.utf8)) != nil
    }

    /// The profile a path belongs to when the path is a part of it that every extension shares: at or inside
    /// `Local Storage` or Firefox's `storage`, or its `Preferences` file.
    private static func profile(sharedBy components: [String]) -> String? {
        let names = components.map { $0.lowercased() }
        let shared = names.lastIndex { $0 == "local storage" || $0 == "storage" }
            ?? (names.last == "preferences" ? names.count - 1 : nil)
        guard let shared, shared > 0 else { return nil }
        return "/" + components[..<shared].joined(separator: "/")
    }
}
