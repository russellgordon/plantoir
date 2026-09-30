namespace Plantoir.Core.Assist;

/// <summary>
/// What a publish set for later does when its moment comes.
/// </summary>
public static class ScheduledRun
{
    /// <summary>
    /// How long a publish set for later waits for another program's build or
    /// publish of the course before it stands down (<c>shared-rules.json</c> →
    /// <c>workLeases.declining.scheduledPublishWait</c>): ten minutes, on the
    /// WALL clock, so a computer that sleeps does not pause the count.
    /// </summary>
    public static readonly TimeSpan LongestWait = TimeSpan.FromSeconds(600);

    /// <summary>How often it looks again while it waits.</summary>
    public static readonly TimeSpan LookAgainEvery = TimeSpan.FromSeconds(15);
}
