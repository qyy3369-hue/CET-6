using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace Goals.Windows.Services;

/// <summary>
/// Minimal SentencePiece Unigram tokenizer driven by a vocab JSON dumped from
/// the model's spiece.model. The pieces carry log-probability scores and the
/// encoder uses Viterbi segmentation, matching the reference tokenizer.
/// </summary>
internal sealed class UnigramTokenizer
{
    private sealed class TrieNode
    {
        public Dictionary<char, TrieNode> Children { get; } = [];
        public int Id = -1;
        public float Score;
    }

    private readonly string[] _tokens;
    private readonly TrieNode _root = new();
    private readonly int _unkId;
    private readonly bool _addDummyPrefix;

    public int UnkId => _unkId;
    public int PadId { get; }
    public int BosId { get; }
    public int EosId { get; }

    public UnigramTokenizer(string jsonPath)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(jsonPath));
        var root = document.RootElement;
        var vocab = root.GetProperty("pieces");
        var count = vocab.GetArrayLength();
        _tokens = new string[count];
        for (var i = 0; i < count; i++)
        {
            var entry = vocab[i];
            var token = entry[0].GetString()!;
            var score = entry.GetArrayLength() > 1 ? entry[1].GetSingle() : -1f;
            _tokens[i] = token;
            var node = _root;
            foreach (var ch in token)
            {
                if (!node.Children.TryGetValue(ch, out var next))
                {
                    next = new TrieNode();
                    node.Children[ch] = next;
                }
                node = next;
            }
            if (node.Id < 0)
            {
                node.Id = i;
                node.Score = score;
            }
        }
        _unkId = root.GetProperty("unk_id").GetInt32();
        PadId = root.GetProperty("pad_id").GetInt32();
        BosId = root.GetProperty("bos_id").GetInt32();
        EosId = root.GetProperty("eos_id").GetInt32();
        _addDummyPrefix = root.TryGetProperty("add_dummy_prefix", out var dummy) ? dummy.GetBoolean() : true;
    }

    public int[] Encode(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormKC);
        if (_addDummyPrefix) normalized = "▁" + normalized;

        var n = normalized.Length;
        var best = new double[n + 1];
        var backPos = new int[n + 1];
        var backId = new int[n + 1];
        Array.Fill(best, double.NegativeInfinity);
        best[0] = 0;
        for (var i = 0; i < n; i++)
        {
            if (double.IsNegativeInfinity(best[i])) continue;
            var node = _root;
            for (var j = i; j < n; j++)
            {
                if (!node.Children.TryGetValue(normalized[j], out node)) break;
                if (node.Id < 0) continue;
                var score = best[i] + node.Score;
                var next = j + 1;
                if (score > best[next])
                {
                    best[next] = score;
                    backPos[next] = i;
                    backId[next] = node.Id;
                }
            }
        }

        if (double.IsNegativeInfinity(best[n]))
            return FallbackGreedy(normalized);

        var ids = new List<int>(n / 2);
        for (var pos = n; pos > 0; pos = backPos[pos]) ids.Add(backId[pos]);
        ids.Reverse();
        return ids.ToArray();
    }

    private int[] FallbackGreedy(string normalized)
    {
        var ids = new List<int>();
        var i = 0;
        while (i < normalized.Length)
        {
            var node = _root;
            var matched = -1;
            var matchedLen = 0;
            for (var j = i; j < normalized.Length; j++)
            {
                if (!node.Children.TryGetValue(normalized[j], out node)) break;
                if (node.Id >= 0)
                {
                    matched = node.Id;
                    matchedLen = j - i + 1;
                }
            }
            if (matched >= 0 && matchedLen > 0)
            {
                ids.Add(matched);
                i += matchedLen;
            }
            else
            {
                ids.Add(_unkId);
                i++;
            }
        }
        return ids.ToArray();
    }

    public string Decode(IReadOnlyList<int> ids)
    {
        var builder = new StringBuilder(ids.Count * 2);
        foreach (var id in ids)
        {
            if (id < 0 || id >= _tokens.Length) continue;
            var token = _tokens[id];
            if (token.Length == 0 || token[0] == '<') continue;
            foreach (var ch in token)
                builder.Append(ch == '▁' ? ' ' : ch);
        }
        return builder.ToString().Trim();
    }
}
