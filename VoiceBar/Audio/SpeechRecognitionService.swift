import Foundation
import Speech
import AVFoundation

final class SpeechRecognitionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var currentLanguage: Locale
    private var levelHandler: ((Float) -> Void)?
    private var lastTranscription: String = ""

    init(language: String) {
        self.currentLanguage = Locale(identifier: language)
        self.speechRecognizer = SFSpeechRecognizer(locale: currentLanguage)
    }

    func updateLanguage(_ languageCode: String) {
        stopStreamingInternal()
        currentLanguage = Locale(identifier: languageCode)
        speechRecognizer = SFSpeechRecognizer(locale: currentLanguage)
    }

    func startStreaming(onResult: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void) {
        self.levelHandler = onLevel

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer unavailable")
            return
        }

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("Speech recognition not authorized")
                return
            }

            DispatchQueue.main.async {
                self?.startRecognitionInternal(onResult: onResult)
            }
        }
    }

    // MARK: - Custom Vocabulary

    /// All contextual strings for the current language, including optional domain modules.
    private var contextualStrings: [String] {
        let lang = currentLanguage.identifier.lowercased()
        let base = lang.hasPrefix("zh") ? chineseBaseTerms : englishBaseTerms
        let domain = urbanPlanningTerms  // toggle this to add/remove urban planning vocabulary
        return base + domain
    }

    /// Urban planning & city renewal professional terminology.
    /// Enabled/disabled via SettingsManager.shared.urbanPlanningEnabled.
    private var urbanPlanningTerms: [String] {
        guard SettingsManager.shared.urbanPlanningEnabled else { return [] }

        return [
            // English urban planning terms
            "Urban Planning", "City Planning", "Urban Renewal", "Urban Regeneration",
            "Urban Redevelopment", "Urban Revitalization", "Urban Redesign",
            "Master Plan", "Comprehensive Plan", "Zoning", "Rezoning", "Land Use",
            "TOD", "Transit-Oriented Development", "Smart City", "Green City",
            "Compact City", "Sprawl", "Infill Development", "Brownfield", "Greenfield",
            "Mixed-Use", "Density", "Floor Area Ratio", "FAR", "Building Coverage Ratio",
            "Setback", "Height Limit", "Planned Unit Development", "PUD",
            "Historic Preservation", "Heritage Conservation", "Adaptive Reuse",
            "Urban Design", "Streetscape", "Public Realm", "Public Space",
            "Green Belt", "Urban Forest", "Park System", "Greenway", "Blueway",
            "Traffic Impact Assessment", "Transportation Planning", "Road Network",
            "Parking", "Bicycle Lane", "Bike Lane", "Pedestrian Zone", "Walkability",
            "Infrastructure", "Municipal Infrastructure", "Utility Underground",
            "Stormwater", "Sewage", "Water Supply", "District Energy",
            "Affordable Housing", "Social Housing", "Public Housing", "Gentrification",
            "Displacement", "Community Engagement", "Public Participation",
            "Stakeholder", "Environmental Impact Assessment", "EIA",
            "Sustainability", "Carbon Neutral", "Net Zero", "Resilience",
            "Climate Adaptation", "Flood Plain", "Coastal Zone", "Wetland",
            "GIS", "Geographic Information System", "Remote Sensing", "Digital Twin",
            "BIM", "Building Information Modeling", "CIM", "City Information Modeling",
            "Cadastral", "Cadastral Map", "Land Survey", "Topographic Survey",
            "Form-Based Code", "Performance Zoning", "Inclusionary Zoning",
            "Transfer of Development Rights", "TDR", "Density Bonus",
            "Urban Growth Boundary", "Smart Growth", "New Urbanism",
            "TOD", "PPP", "Public-Private Partnership", "BOT", "Build-Operate-Transfer",
            "Real Estate Development", "Property Development", "Land Development",
            "Site Plan", "Master Plan", "Concept Plan", "Schematic Design",
            "Development Permit", "Building Permit", "Planning Permit", "Zoning Certificate",
            "Floor Area", "Plot Ratio", "Building Height", "Storey", "Gross Floor Area",
            "Landreadjustment", "Land Consolidation", "Land Banking",
            "Slum Upgrading", "Shanty Town", "Informal Settlement", "城中村",
            "Urban Village", "Peri-urban", "Suburban", "Exurban",
            "Downtown", "Central Business District", "CBD", "Old Town", "Historic District",
            "Conservation Area", "Scenic Area", "Ecological Zone", "Agricultural Zone",
            "Industrial Zone", "Commercial Zone", "Residential Zone", "Mixed-Use Zone",
            "Administrative District", "Jurisdiction", "Municipal Boundary",
            "Urban Management", "City Governance", "Urban Policy",
            "Housing Policy", "Land Policy", "Transportation Policy",
            "Regional Planning", "Metropolitan Planning", "City Cluster",
            "Mega-City", "Megacity", "Satellite City", "New Town", "New City",
            "Revitalization", "Redevelopment", "Retrofitting", "Refurbishment",

            // Chinese urban planning terms
            "城市规划", "城市更新", "城市设计", "城乡规划", "国土空间规划",
            "总体规划", "控制性详细规划", "修建性详细规划", "分区规划", "战略规划",
            "城市设计导则", "城市意象", "空间句法", "TOD", "轨道交通导向开发",
            "精明增长", "紧凑城市", "低碳城市", "海绵城市", "智慧城市", "生态城市",
            "绿色建筑", "被动式建筑", "近零能耗建筑",
            "用地性质", "用地红线", "三旧改造", "三线划定", "三区三线",
            "城镇开发边界", "永久基本农田", "生态保护红线",
            "容积率", "建筑密度", "绿地率", "建筑限高", "退线", "日照间距",
            "用地兼容性", "混合用地", "兼容性用地",
            "旧城更新", "旧工业区更新", "城中村改造", "棚户区改造", "老旧小区改造",
            "微更新", "有机更新", "渐进式更新", "单元式更新",
            "土地一级开发", "土地二级开发", "熟地", "毛地", "净地",
            "招拍挂", "协议出让", "划拨用地", "集体建设用地", "农用地转用",
            "土地增值税", "耕地占用税", "土地出让金", "地价评估",
            "房屋征收", "征地拆迁", "补偿安置", "产权置换", "货币补偿",
            "回迁房", "安置房", "保障房", "公租房", "共有产权房", "经适房",
            "户型", "套型", "建筑面积", "套内面积", "得房率",
            "基础设施", "市政设施", "综合管廊", "海绵设施", "雨污分流",
            "交通影响评价", "交通组织", "路网密度", "道路红线", "街道高宽比",
            "慢行系统", "步行街", "骑行道", "停车位", "充电桩",
            "公共空间", "开放空间", "口袋公园", "街旁绿地", "社区公园", "综合公园",
            "滨水空间", "蓝绿空间", "生态廊道", "生态斑块", "城市绿心",
            "历史文化保护", "历史建筑", "历史街区", "文保单位", "工业遗产",
            "活化利用", "功能置换", "织补", "针灸式更新",
            "竖向设计", "场地设计", "景观设计", "海绵设计",
            "BIM", "CIM", "GIS", "倾斜摄影", "实景三维", "数字孪生城市",
            "三维地籍", "地籍测量", "地形测量", "房产测绘",
            "控高", "限高", "天际线", "视廊", "通视分析",
            "日照分析", "日照标准", "大寒日", "冬至日",
            "开发强度", "强度分区", "高度分区", "密度分区",
            "规划条件", "规划许可证", "建设工程规划许可证", "施工许可证",
            "规划核实", "竣工验收", "规划变更", "规划调整",
            "公众参与", "社会稳定性评估", "环境影响评价", "交通影响评价",
            "可研报告", "初步设计", "施工图设计", "方案设计",
            "PPP", "政府和社会资本合作", "特许经营", "BOT", "EPC",
            " TOD", "SOD", "XOD", "EOD", "WOD",
            "城市体检", "城市更新评估", "绩效评价", "实施评估",
            "规划一张图", "时空信息平台", "城市信息模型平台",
            "元胞自动机", "多智能体", "城市模拟", "情景规划",
            "精明收缩", "人口流失", "空心化", "绅士化",
            "职住平衡", "产城融合", "15分钟生活圈", "完整社区",
            "韧性城市", "防灾减灾", "综合防灾", "抗震防灾",
            "城市更新条例", "城乡规划法", "土地管理法", "房地产管理法",
            "容积率奖励", "开发权转移", "密度补偿", "混合激励",
            "红线", "蓝线", "绿线", "紫线", "黄线", "黑线",
            "开发边界", "增长边界", "禁建区", "限建区", "适建区",
            "五线", "六线", "多规合一", "国土一张图"
        ]
    }

    private let englishBaseTerms: [String] = [
        "GitHub", "GitLab", "Bitbucket", "Git",
        "Python", "JavaScript", "TypeScript", "Swift", "Go", "Rust", "Ruby", "PHP",
        "API", "JSON", "XML", "HTML", "CSS", "SQL", "NoSQL", "REST API", "GraphQL",
        "AWS", "GCP", "Azure", "Docker", "Kubernetes", "Linux", "macOS", "iOS",
        "OpenAI", "Claude", "ChatGPT", "LLM", "TensorFlow", "PyTorch",
        "Copilot", "Cursor", "VS Code", "Xcode", "React", "Vue", "Node.js",
        "CI/CD", "DevOps", "Microservices", "Serverless",
        "Blockchain", "IoT", "VR", "AR", "Metaverse", "Digital Twin",
        "SaaS", "PaaS", "IaaS", "OKR", "KPI", "Scrum", "Kanban",
        "JWT", "OAuth", "HTTPS", "SSH", "VPN", "DNS", "CDN"
    ]

    private let chineseBaseTerms: [String] = [
        "Python", "JavaScript", "TypeScript", "Swift", "Go", "Rust", "API", "JSON",
        "GitHub", "Git", "Docker", "Kubernetes", "Linux", "macOS", "iOS", "React",
        "Vue", "Node.js", "MySQL", "PostgreSQL", "MongoDB", "Redis", "AWS", "Azure",
        "HTTP", "HTTPS", "URL", "HTML", "CSS", "SQL", "NoSQL", "SaaS",
        "OpenAI", "Claude", "ChatGPT", "LLM", "TensorFlow", "PyTorch",
        "Copilot", "Cursor", "VS Code", "Xcode", "SwiftUI", "UIKit",
        "CI/CD", "DevOps", "微服务", "无服务器", "区块链", "人工智能",
        "机器学习", "深度学习", "神经网络", "大语言模型", "向量数据库",
        "物联网", "虚拟现实", "增强现实", "元宇宙", "数字孪生",
        "低代码", "无代码", "产品经理", "项目经理", "架构师", "全栈"
    ]

    // MARK: - Recognition

    private func startRecognitionInternal(onResult: @escaping (String) -> Void) {
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = AVAudioEngine()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
            // Feed contextual strings so SFSpeechRecognizer scores them higher
            request.contextualStrings = contextualStrings
        }

        guard let engine = audioEngine else { return }
        let inputNode = engine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            var isFinal = false
            if let result = result {
                let text = result.bestTranscription.formattedString
                self?.lastTranscription = text
                onResult(text)
                isFinal = result.isFinal
            }
            if error != nil || isFinal {
                self?.stopStreamingInternal()
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.calculateRMS(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Typical speech RMS: 0.005–0.05. Map 0→0, 0.03→1 for good visual range
        let normalizedLevel = min(1.0, max(0.0, rms / 0.03))

        DispatchQueue.main.async { [weak self] in
            self?.levelHandler?(normalizedLevel)
        }
    }

    func stopStreaming(completion: @escaping (String) -> Void) {
        let finalText = lastTranscription
        lastTranscription = ""
        stopStreamingInternal()
        completion(finalText)
    }

    private func stopStreamingInternal() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        levelHandler = nil
        lastTranscription = ""
    }
}
