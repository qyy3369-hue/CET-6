using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace Goals.Windows.Services;

/// <summary>
/// Runs a Marian (OPUS-MT) ja→zh seq2seq model as ONNX: source tokens are
/// encoded once, then the decoder greedily produces target tokens while caching
/// its key/value tensors until the EOS token appears.
/// </summary>
internal sealed class OnnxSeq2SeqTranslator : IDisposable
{
    private const int MaxDecoderSteps = 64;

    private readonly UnigramTokenizer _source;
    private readonly UnigramTokenizer _target;
    private readonly InferenceSession _encoder;
    private readonly InferenceSession _decoder;
    private readonly InferenceSession _decoderWithPast;
    private readonly string _encoderInputIds;
    private readonly string _encoderAttentionMask;
    private readonly string _encoderHiddenOutput;
    private readonly string _decoderInputIds;
    private readonly string _decoderEncoderHidden;
    private readonly string _decoderEncoderAttention;
    private readonly string[] _decoderPastInputs;
    private readonly string _decoderLogitsOutput;

    public OnnxSeq2SeqTranslator(string modelDirectory)
    {
        _source = new UnigramTokenizer(Path.Combine(modelDirectory, "source_vocab.json"));
        _target = new UnigramTokenizer(Path.Combine(modelDirectory, "target_vocab.json"));
        _encoder = new InferenceSession(Path.Combine(modelDirectory, "encoder_model.onnx"));
        _decoder = new InferenceSession(Path.Combine(modelDirectory, "decoder_model.onnx"));
        _decoderWithPast = new InferenceSession(Path.Combine(modelDirectory, "decoder_with_past_model.onnx"));

        _encoderInputIds = FindInput(_encoder, n => n.Contains("input_ids", StringComparison.OrdinalIgnoreCase));
        _encoderAttentionMask = FindInput(_encoder, n => n.Contains("attention_mask", StringComparison.OrdinalIgnoreCase));
        _encoderHiddenOutput = FindOutput(_encoder, n => n.Contains("hidden", StringComparison.OrdinalIgnoreCase));

        _decoderInputIds = FindInput(_decoder, n => n.Contains("input_ids", StringComparison.OrdinalIgnoreCase) && !n.Contains("decoder_attention", StringComparison.OrdinalIgnoreCase));
        _decoderEncoderHidden = FindInput(_decoder, n => n.Contains("encoder_hidden", StringComparison.OrdinalIgnoreCase));
        _decoderEncoderAttention = FindInput(_decoder, n => n.Contains("encoder", StringComparison.OrdinalIgnoreCase) && n.Contains("attention_mask", StringComparison.OrdinalIgnoreCase));
        _decoderPastInputs = _decoderWithPast.InputMetadata.Keys.Where(n => n.Contains("past", StringComparison.OrdinalIgnoreCase)).ToArray();
        _decoderLogitsOutput = FindOutput(_decoder, n => n.Contains("logits", StringComparison.OrdinalIgnoreCase));
    }

    private static string FindInput(InferenceSession session, Func<string, bool> predicate) =>
        session.InputMetadata.Keys.FirstOrDefault(predicate) ?? session.InputMetadata.Keys.First();

    private static string FindOutput(InferenceSession session, Func<string, bool> predicate) =>
        session.OutputMetadata.Keys.FirstOrDefault(predicate) ?? session.OutputMetadata.Keys.First();

    public string Translate(string japanese)
    {
        // Strip dictionary metadata that is not part of the gloss itself:
        // definition-number markers such as ①-⑩ and trailing plain digits.
        var source = Regex.Replace(japanese, @"[①②③④⑤⑥⑦⑧⑨⑩]", "");
        source = source.Trim();
        // Dictionary glosses often end in the "こと" nominalizer ("…すること。"),
        // which trips up the NMT; translating the clause alone is more accurate.
        if (source.EndsWith("こと。", StringComparison.Ordinal)) source = source[..^3];
        else if (source.EndsWith("こと", StringComparison.Ordinal)) source = source[..^2];

        var encoderIds = _source.Encode(source).Concat(new[] { _source.EosId }).ToArray();
        var n = encoderIds.Length;
        var inputIdTensor = new DenseTensor<long>(encoderIds.Select(x => (long)x).ToArray(), new[] { 1, n });
        var attentionTensor = new DenseTensor<long>(Enumerable.Repeat(1L, n).ToArray(), new[] { 1, n });

        var encoderInputs = new List<NamedOnnxValue>
        {
            NamedOnnxValue.CreateFromTensor(_encoderInputIds, inputIdTensor),
            NamedOnnxValue.CreateFromTensor(_encoderAttentionMask, attentionTensor)
        };
        using var encoderOutputs = _encoder.Run(encoderInputs);
        var hiddenTensor = encoderOutputs.First(x => x.Name == _encoderHiddenOutput).AsTensor<float>();
        var hidden = hiddenTensor.ToArray();
        var hiddenDims = hiddenTensor.Dimensions.ToArray();

        var generated = new List<int> { _target.EosId };
        List<float[]> decoderPast = [];
        List<int[]> decoderPastDims = [];
        List<float[]> encoderPast = [];
        List<int[]> encoderPastDims = [];
        var decoder = _decoder;

        for (var step = 0; step < MaxDecoderSteps; step++)
        {
            var lastId = generated[^1];
            var inputs = new List<NamedOnnxValue>
            {
                NamedOnnxValue.CreateFromTensor(_decoderInputIds, new DenseTensor<long>(new[] { (long)lastId }, new[] { 1, 1 })),
                NamedOnnxValue.CreateFromTensor(_decoderEncoderAttention, attentionTensor)
            };
            if (step == 0)
            {
                inputs.Add(NamedOnnxValue.CreateFromTensor(_decoderEncoderHidden, new DenseTensor<float>(hidden.AsMemory(), hiddenDims)));
            }
            else
            {
                var decoderIndex = 0;
                var encoderIndex = 0;
                for (var i = 0; i < _decoderPastInputs.Length; i++)
                {
                    if (_decoderPastInputs[i].Contains(".encoder.", StringComparison.OrdinalIgnoreCase))
                        inputs.Add(NamedOnnxValue.CreateFromTensor(_decoderPastInputs[i], new DenseTensor<float>(encoderPast[encoderIndex].AsMemory(), encoderPastDims[encoderIndex++])));
                    else
                        inputs.Add(NamedOnnxValue.CreateFromTensor(_decoderPastInputs[i], new DenseTensor<float>(decoderPast[decoderIndex].AsMemory(), decoderPastDims[decoderIndex++])));
                }
            }

            using var outputs = decoder.Run(inputs);
            var logits = outputs.First(x => x.Name == _decoderLogitsOutput).AsTensor<float>();
            var nextId = ArgMax(logits);
            generated.Add(nextId);
            if (nextId == _target.EosId) break;

            var presents = outputs.Where(x => x.Name.Contains("present", StringComparison.OrdinalIgnoreCase)).ToList();
            if (presents.Count == 0) break;
            if (step == 0)
            {
                encoderPast = presents.Where(x => x.Name.Contains(".encoder.", StringComparison.OrdinalIgnoreCase)).Select(x => x.AsTensor<float>().ToArray()).ToList();
                encoderPastDims = presents.Where(x => x.Name.Contains(".encoder.", StringComparison.OrdinalIgnoreCase)).Select(x => x.AsTensor<float>().Dimensions.ToArray()).ToList();
            }
            decoderPast = presents.Where(x => x.Name.Contains(".decoder.", StringComparison.OrdinalIgnoreCase)).Select(x => x.AsTensor<float>().ToArray()).ToList();
            decoderPastDims = presents.Where(x => x.Name.Contains(".decoder.", StringComparison.OrdinalIgnoreCase)).Select(x => x.AsTensor<float>().Dimensions.ToArray()).ToList();
            decoder = _decoderWithPast;
        }

        var outputIds = generated
            .Skip(1)
            .Where(id => id != _target.EosId && id != _target.UnkId && id != _target.PadId)
            .ToArray();
        return _target.Decode(outputIds);
    }

    private static int ArgMax(Tensor<float> logits)
    {
        var dims = logits.Dimensions.ToArray();
        var vocab = dims[^1];
        var offset = (int)(logits.Length - vocab);
        var best = float.NegativeInfinity;
        var bestIndex = 0;
        for (var v = 0; v < vocab; v++)
        {
            var value = logits.GetValue(offset + v);
            if (value > best)
            {
                best = value;
                bestIndex = v;
            }
        }
        return bestIndex;
    }

    public void Dispose()
    {
        _encoder.Dispose();
        _decoder.Dispose();
        _decoderWithPast.Dispose();
    }
}
