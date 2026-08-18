using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// Reading a tool's two halves apart, the way the app does.
///
/// A test that asserts on the whole of what a tool returned is asserting on
/// the MODEL's half — which is the half nobody reads. When the question is
/// "what does the teacher see", ask for <see cref="Summary"/>.
/// </summary>
internal static class ToolAnswers
{
    /// <summary>What the model is handed: the result's text content.</summary>
    public static string Detail(this CallToolResult result)
    {
        var text = new System.Text.StringBuilder();
        foreach (var block in result.Content)
            if (block is TextContentBlock piece) text.AppendLine(piece.Text);
        return text.ToString().TrimEnd();
    }

    /// <summary>
    /// The one line the teacher reads. A tool that says the same thing to
    /// both sends no <c>_meta</c>, and that absence means "show the text".
    /// </summary>
    public static string Summary(this CallToolResult result)
    {
        if (result.Meta?[AssistToolAnswer.TeacherSummaryKey]?.GetValue<string>() is { Length: > 0 } summary)
            return summary;
        return result.Detail();
    }
}
