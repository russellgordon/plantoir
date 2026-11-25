using System.Reflection;
using System.Runtime.CompilerServices;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #990 review 3, low 3: the course's noun has no default on the in-app
/// assistant or the runner, so a site that builds either must name it, and a
/// club is never told "the Section or Classes menu" by a site that forgot.
/// The compiler enforces it (CS9035 at every site that leaves it out); this
/// pins that the property stays required. MUST FAIL with the
/// <c>= ClassNoun.Class</c> default put back in place of <c>required</c>.
/// </summary>
public class CourseNounRequiredTests
{
    [Theory]
    [InlineData(typeof(AssistAgent))]
    [InlineData(typeof(AssistToolRunner))]
    public void TheCourseNounMustBeNamedWhereverOneIsBuilt(Type type)
    {
        var property = type.GetProperty("CourseNoun", BindingFlags.Public | BindingFlags.Instance)!;
        Assert.NotNull(property.GetCustomAttribute<RequiredMemberAttribute>());
    }
}
