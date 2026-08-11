using System.Collections.ObjectModel;
using Goals.Windows.Models;

namespace Goals.Windows.Services;

public static class DefaultDataFactory
{
    public static AppState Create()
    {
        var englishPlan = new PlanSheet
        {
            Id = "cet6-plan-01",
            Title = "计划表 01",
            Content = "每天完成词汇复习与一项专项训练；周末进行整套真题和错题复盘。",
            UpdatedAt = DateTime.Now
        };
        var japanesePlan = new PlanSheet
        {
            Id = "n4-plan-01",
            Title = "N4 基础计划",
            Content = "每天复习 12 个词语，完成假名朗读与例句跟读；每三天集中回顾错词。",
            UpdatedAt = DateTime.Now
        };

        var state = new AppState
        {
            CurrentTrackId = "cet6",
            Tracks =
            [
                new StudyTrack
                {
                    Id = "cet6", Title = "CET-6 备考", Mode = LearningMode.English,
                    Category = "考试冲刺", Focus = "词汇、阅读、听力与输出并进，保持每天可完成的小步节奏。",
                    Plans = [englishPlan]
                },
                new StudyTrack
                {
                    Id = "japanese-n4", Title = "日语 N4", Mode = LearningMode.Japanese,
                    Category = "JLPT N4", Focus = "以词汇识别、假名朗读、例句理解和间隔复习为核心。",
                    Plans = [japanesePlan]
                }
            ]
        };

        state.Tasks =
        [
            Task("cet6", englishPlan.Id, 0, "08:10", "复习 20 个 CET-6 到期闪卡"),
            Task("cet6", englishPlan.Id, 0, "12:40", "精读一篇六级短文并整理生词"),
            Task("cet6", englishPlan.Id, 0, "19:30", "完成一组听力 Section B/C"),
            Task("cet6", englishPlan.Id, 0, "21:00", "复盘今天的错词收藏"),
            Task("cet6", englishPlan.Id, 1, "19:30", "完成一组仔细阅读"),
            Task("japanese-n4", japanesePlan.Id, 0, "07:40", "朗读并复习 12 个 N4 词语"),
            Task("japanese-n4", japanesePlan.Id, 0, "18:30", "跟读 5 条日语例句"),
            Task("japanese-n4", japanesePlan.Id, 0, "21:10", "完成日语错词回炉"),
            Task("japanese-n4", japanesePlan.Id, 1, "20:00", "复习动词て形相关词语")
        ];

        foreach (var word in EnglishWords()) state.Words.Add(word);
        foreach (var word in JapaneseWords()) state.Words.Add(word);
        foreach (var word in state.Words)
            state.Progress.Add(new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today });

        state.FavoriteWordIds.Add("en-substantial");
        state.FavoriteWordIds.Add("ja-keiken");
        return state;
    }

    private static StudyTask Task(string track, string plan, int offset, string time, string title) => new()
    {
        TrackId = track, PlanId = plan, Date = DateTime.Today.AddDays(offset), Time = time, Title = title, Source = "sample"
    };

    private static VocabularyWord E(string id, string word, string phonetic, string pos, string meaning, string example, string translation, string tag, int difficulty = 3) => new()
    {
        Id = "en-" + id, TrackId = "cet6", Word = word, Phonetic = phonetic, PartOfSpeech = pos,
        Meaning = meaning, Example = example, ExampleTranslation = translation, Tag = tag, Difficulty = difficulty
    };

    private static IEnumerable<VocabularyWord> EnglishWords()
    {
        yield return E("adequate", "adequate", "/ˈædɪkwət/", "adj.", "足够的；合格的", "The evidence is adequate to support the conclusion.", "这些证据足以支持该结论。", "写作替换", 3);
        yield return E("allocate", "allocate", "/ˈæləkeɪt/", "v.", "分配；拨出", "Students should allocate time for regular review.", "学生应当为定期复习分配时间。", "计划表达", 3);
        yield return E("coherent", "coherent", "/kəʊˈhɪərənt/", "adj.", "连贯的；条理清楚的", "A coherent argument is easier to understand.", "连贯的论点更容易理解。", "写作高频", 4);
        yield return E("compelling", "compelling", "/kəmˈpelɪŋ/", "adj.", "令人信服的；引人入胜的", "She presented a compelling reason for the change.", "她提出了一个令人信服的变革理由。", "阅读高频", 4);
        yield return E("derive", "derive", "/dɪˈraɪv/", "v.", "获得；源自", "Many English words derive from Latin roots.", "许多英语单词源自拉丁词根。", "词根", 3);
        yield return E("diminish", "diminish", "/dɪˈmɪnɪʃ/", "v.", "减少；削弱", "Regular breaks can diminish mental fatigue.", "定时休息可以减轻精神疲劳。", "阅读高频", 4);
        yield return E("elaborate", "elaborate", "/ɪˈlæbərət/", "adj./v.", "详尽的；详细说明", "Could you elaborate on your main point?", "你能详细说明一下主要观点吗？", "写作表达", 3);
        yield return E("facilitate", "facilitate", "/fəˈsɪlɪteɪt/", "v.", "促进；使便利", "Digital tools facilitate access to information.", "数字工具让获取信息更加便利。", "写作替换", 4);
        yield return E("feasible", "feasible", "/ˈfiːzəbl/", "adj.", "可行的；办得到的", "The team proposed a feasible solution.", "团队提出了一个可行的解决方案。", "写作高频", 3);
        yield return E("inevitable", "inevitable", "/ɪnˈevɪtəbl/", "adj.", "不可避免的", "Some degree of uncertainty is inevitable.", "一定程度的不确定性不可避免。", "阅读高频", 3);
        yield return E("intricate", "intricate", "/ˈɪntrɪkət/", "adj.", "错综复杂的；精细的", "The device contains an intricate network of sensors.", "该设备包含一套复杂的传感器网络。", "高难词", 5);
        yield return E("notion", "notion", "/ˈnəʊʃn/", "n.", "观念；看法", "The study challenges the traditional notion of success.", "这项研究挑战了传统的成功观。", "阅读高频", 3);
        yield return E("prevalent", "prevalent", "/ˈprevələnt/", "adj.", "普遍的；盛行的", "Online learning is increasingly prevalent.", "在线学习越来越普遍。", "写作高频", 4);
        yield return E("profound", "profound", "/prəˈfaʊnd/", "adj.", "深刻的；影响深远的", "Technology has had a profound impact on communication.", "科技对交流产生了深远影响。", "写作升级", 4);
        yield return E("resilient", "resilient", "/rɪˈzɪliənt/", "adj.", "有韧性的；能迅速恢复的", "Resilient learners view mistakes as useful feedback.", "有韧性的学习者把错误视为有用反馈。", "写作升级", 4);
        yield return E("substantial", "substantial", "/səbˈstænʃl/", "adj.", "大量的；实质性的", "A substantial improvement requires consistent practice.", "显著进步需要持续练习。", "写作升级", 5);
        yield return E("tentative", "tentative", "/ˈtentətɪv/", "adj.", "暂定的；试探性的", "We reached a tentative agreement.", "我们达成了初步协议。", "阅读高频", 4);
        yield return E("undermine", "undermine", "/ˌʌndəˈmaɪn/", "v.", "逐渐削弱；损害", "Lack of sleep can undermine concentration.", "睡眠不足会削弱专注力。", "阅读高频", 4);
        yield return E("versatile", "versatile", "/ˈvɜːsətaɪl/", "adj.", "多才多艺的；用途广泛的", "The tablet is a versatile learning tool.", "平板电脑是一种多用途学习工具。", "写作替换", 4);
        yield return E("viable", "viable", "/ˈvaɪəbl/", "adj.", "切实可行的；能生存的", "Public transport is a viable alternative to driving.", "公共交通是开车之外的可行选择。", "写作高频", 4);
    }

    private static VocabularyWord J(string id, string word, string reading, string romaji, string pos, string meaning, string example, string translation, string tag, int difficulty = 3) => new()
    {
        Id = "ja-" + id, TrackId = "japanese-n4", Word = word, Reading = reading, Romanization = romaji,
        PartOfSpeech = pos, Meaning = meaning, Example = example, ExampleTranslation = translation, Tag = tag, Difficulty = difficulty
    };

    private static IEnumerable<VocabularyWord> JapaneseWords()
    {
        yield return J("aisatsu", "挨拶", "あいさつ", "aisatsu", "名词/サ变", "寒暄；问候", "朝、先生に挨拶しました。", "早上向老师问好了。", "N4 日常", 2);
        yield return J("akiramuru", "諦める", "あきらめる", "akirameru", "一段动词", "放弃；死心", "最後まで諦めないでください。", "请不要放弃到最后。", "N4 动词", 3);
        yield return J("anzen", "安全", "あんぜん", "anzen", "名词/形动", "安全", "安全な場所で待ってください。", "请在安全的地方等候。", "N4 日常", 2);
        yield return J("iken", "意見", "いけん", "iken", "名词", "意见；见解", "あなたの意見を聞かせてください。", "请告诉我你的意见。", "N4 表达", 2);
        yield return J("ugoku", "動く", "うごく", "ugoku", "五段动词", "动；运转", "この時計はまだ動いています。", "这块表还在走。", "N4 动词", 2);
        yield return J("utsusu", "移す", "うつす", "utsusu", "五段动词", "移动；转移", "机を窓の近くへ移しました。", "把桌子移到了窗边。", "N4 动词", 3);
        yield return J("erabu", "選ぶ", "えらぶ", "erabu", "五段动词", "选择；挑选", "好きな色を一つ選んでください。", "请选择一种喜欢的颜色。", "N4 动词", 2);
        yield return J("okureru", "遅れる", "おくれる", "okureru", "一段动词", "迟到；延误", "電車が十分遅れました。", "电车晚点了十分钟。", "N4 交通", 2);
        yield return J("odoroku", "驚く", "おどろく", "odoroku", "五段动词", "吃惊；惊讶", "そのニュースを聞いて驚きました。", "听到那条消息后很吃惊。", "N4 情绪", 3);
        yield return J("kaigi", "会議", "かいぎ", "kaigi", "名词", "会议", "午後三時から会議があります。", "下午三点开始有会议。", "N4 工作", 2);
        yield return J("kanarazu", "必ず", "かならず", "kanarazu", "副词", "一定；必定", "出かける前に必ず鍵を確認します。", "出门前一定检查钥匙。", "N4 副词", 2);
        yield return J("kankei", "関係", "かんけい", "kankei", "名词/サ变", "关系；关联", "二つの問題には深い関係があります。", "两个问题之间有很深的关系。", "N4 抽象", 3);
        yield return J("keiken", "経験", "けいけん", "keiken", "名词/サ变", "经验；经历", "日本で働いた経験があります。", "我有在日本工作的经历。", "N4 重点", 3);
        yield return J("kekka", "結果", "けっか", "kekka", "名词", "结果", "試験の結果は来週分かります。", "考试结果下周揭晓。", "N4 抽象", 2);
        yield return J("kenkyuu", "研究", "けんきゅう", "kenkyuu", "名词/サ变", "研究", "大学で環境問題を研究しています。", "在大学研究环境问题。", "N4 学习", 3);
        yield return J("koujou", "工場", "こうじょう", "koujou", "名词", "工厂", "父は自動車の工場で働いています。", "父亲在汽车工厂工作。", "N4 场所", 2);
        yield return J("kowasu", "壊す", "こわす", "kowasu", "五段动词", "弄坏；破坏", "弟が私の時計を壊しました。", "弟弟弄坏了我的手表。", "N4 动词", 3);
        yield return J("sagasu", "探す", "さがす", "sagasu", "五段动词", "寻找", "駅の近くで部屋を探しています。", "正在车站附近找房间。", "N4 动词", 2);
        yield return J("shibaraku", "暫く", "しばらく", "shibaraku", "副词", "暂时；一会儿；许久", "しばらくここで待っていてください。", "请暂时在这里等候。", "N4 副词", 3);
        yield return J("junbi", "準備", "じゅんび", "junbi", "名词/サ变", "准备", "旅行の準備はもう終わりました。", "旅行的准备已经结束了。", "N4 日常", 2);
        yield return J("shoukai", "紹介", "しょうかい", "shoukai", "名词/サ变", "介绍", "友達においしい店を紹介しました。", "向朋友介绍了一家好吃的店。", "N4 表达", 2);
        yield return J("setsumei", "説明", "せつめい", "setsumei", "名词/サ变", "说明；解释", "使い方を分かりやすく説明します。", "清楚地说明使用方法。", "N4 表达", 2);
        yield return J("sodateru", "育てる", "そだてる", "sodateru", "一段动词", "培育；养育", "庭で野菜を育てています。", "在院子里种蔬菜。", "N4 动词", 3);
        yield return J("taisetsu", "大切", "たいせつ", "taisetsu", "形容动词", "重要；珍贵", "時間を大切に使いましょう。", "让我们珍惜时间吧。", "N4 形容", 2);
        yield return J("tashikameru", "確かめる", "たしかめる", "tashikameru", "一段动词", "确认；查明", "住所をもう一度確かめました。", "再次确认了地址。", "N4 动词", 3);
        yield return J("tsuzukeru", "続ける", "つづける", "tsuzukeru", "一段动词", "继续；持续", "毎日日本語の勉強を続けています。", "每天坚持学习日语。", "N4 动词", 2);
        yield return J("tsutaeru", "伝える", "つたえる", "tsutaeru", "一段动词", "传达；告诉", "先生に予定の変更を伝えました。", "把日程变更告诉了老师。", "N4 表达", 3);
        yield return J("teinei", "丁寧", "ていねい", "teinei", "形容动词", "礼貌；细致", "店員が丁寧に説明してくれました。", "店员细致地给我作了说明。", "N4 形容", 2);
        yield return J("todokeru", "届ける", "とどける", "todokeru", "一段动词", "送到；递交；报告", "忘れ物を交番に届けました。", "把遗失物送到了派出所。", "N4 动词", 3);
        yield return J("nareru", "慣れる", "なれる", "nareru", "一段动词", "习惯；适应", "新しい生活に少しずつ慣れました。", "逐渐习惯了新生活。", "N4 动词", 3);
        yield return J("hakobu", "運ぶ", "はこぶ", "hakobu", "五段动词", "搬运；运送", "この箱を二階へ運んでください。", "请把这个箱子搬到二楼。", "N4 动词", 2);
        yield return J("fukuzatsu", "複雑", "ふくざつ", "fukuzatsu", "形容动词", "复杂", "この機械の使い方は少し複雑です。", "这台机器的使用方法有点复杂。", "N4 形容", 3);
        yield return J("machigaeru", "間違える", "まちがえる", "machigaeru", "一段动词", "弄错；做错", "電話番号を間違えてしまいました。", "不小心弄错了电话号码。", "N4 动词", 2);
        yield return J("moushikomu", "申し込む", "もうしこむ", "moushikomu", "五段动词", "申请；报名", "インターネットで試験に申し込みました。", "在网上报名了考试。", "N4 重点", 4);
        yield return J("yakusoku", "約束", "やくそく", "yakusoku", "名词/サ变", "约定；承诺", "友達と駅で会う約束をしました。", "和朋友约好在车站见面。", "N4 日常", 2);
        yield return J("riyuu", "理由", "りゆう", "riyuu", "名词", "理由；原因", "遅れた理由を話してください。", "请说明迟到的原因。", "N4 抽象", 2);
    }
}
