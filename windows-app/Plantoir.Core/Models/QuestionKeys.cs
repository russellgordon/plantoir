namespace Plantoir.Core.Models;

/// <summary>
/// Which key answers what in the New Course wizard (#979), the mac's two
/// rules in <c>NewCourseWizardView</c> (#987 and its review), so the
/// Windows wizard and the unit suite read one statement of them.
/// </summary>
public static class QuestionKeys
{
    /// <summary>
    /// Create Course takes Enter once the form is complete (the mac's D32:
    /// Apple's HIG, Buttons, Role, "the button people are most likely to
    /// choose"), and not while the course-code list is drawn, where Enter
    /// belongs to the list (the #987 review: measured on the mac, a default
    /// button took the Return meant for the highlighted code and made the
    /// course). The mac's <c>createCourseIsTheDefault</c>.
    /// </summary>
    public static bool CreateCourseIsTheDefault(bool formIsComplete, bool suggestionsAreShown)
    {
        if (suggestionsAreShown) return false;
        return formIsComplete;
    }

    /// <summary>
    /// Whether Escape answers the wizard's Cancel: not while the code list is
    /// drawn (the list's own Escape first, <see cref="PickerEscape"/>), and not
    /// while the course is being made (Russell, 2026-11-18, on the #987
    /// review: Escape does nothing then; a click on Cancel still stops it).
    /// The mac's <c>cancelAnswersEscape</c>.
    /// </summary>
    public static bool WizardEscapeIsCancel(bool suggestionsAreShown, bool isCreating)
    {
        if (suggestionsAreShown || isCreating) return false;
        return true;
    }
}
