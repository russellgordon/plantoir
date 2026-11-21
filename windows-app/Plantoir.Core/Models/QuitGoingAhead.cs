namespace Plantoir.Core.Models;

/// <summary>
/// Whether the teacher's quit has gone ahead (#928 items 6 and 7, the mac's
/// <c>isTerminating</c>): while it has, a preview start parked behind an old
/// stop starts nothing, and every repair's Preview Again is abandoned.
///
/// <para>The window's closing handler asks through one <see cref="Pass"/> per
/// time it runs. Set in one place (<see cref="Pass.GoAhead"/>) and cleared in
/// one place (the pass's end): a pass that ends without saying the close went
/// through, was handed to the next pass, or was not a quit at all TAKES THE
/// QUIT BACK. So no way out of the quit question that leaves the app running
/// can leave the quit set (the review's M1: Keep Working on the second pass,
/// after the wait for a tools copy, did, and Preview then started nothing for
/// the life of the process).</para>
/// </summary>
public sealed class QuitGoingAhead
{
    // MARK: - Stored properties

    /// <summary>The app's one record.</summary>
    public static QuitGoingAhead Shared { get; } = new(PreviewAgainPresses.Shared);

    private readonly PreviewAgainPresses _presses;

    /// <summary>True from the moment a pass lets the quit go ahead until a pass takes it back.</summary>
    public bool HasGoneAhead { get; private set; }

    /// <summary>
    /// The window whose pass last handed the quit on to its next close, until
    /// that window's next pass begins (#928 review 2, L11).
    /// </summary>
    private object? _handedOnBy;

    // MARK: - Initializer

    public QuitGoingAhead(PreviewAgainPresses presses) => _presses = presses;

    // MARK: - Functions

    /// <summary>
    /// One run of the closing handler of <paramref name="window"/>.
    /// <paramref name="whenTakenBack"/> runs if the pass takes the quit back.
    /// </summary>
    public Pass BeginPass(Action whenTakenBack, object? window = null)
    {
        bool handedThisQuit = window is not null && ReferenceEquals(_handedOnBy, window);
        if (handedThisQuit) _handedOnBy = null;
        return new Pass(this, whenTakenBack, window, handedThisQuit);
    }

    /// <summary>How one pass of the closing handler ended.</summary>
    public enum Ending
    {
        /// <summary>The window stays up and the app runs on: the quit is taken back. What a pass ends as unless it says otherwise.</summary>
        TakenBack,
        /// <summary>The close was let through: the app quits.</summary>
        GoesThrough,
        /// <summary>The pass closed the window again; the pass that close runs decides.</summary>
        HandedOn,
        /// <summary>This close is not the quit (another window remains, or a second close while the first waits).</summary>
        NotAQuit,
    }

    /// <summary>One pass; dispose it when the handler is done, however it is done.</summary>
    public sealed class Pass : IDisposable
    {
        // MARK: - Stored properties

        private readonly QuitGoingAhead _quit;
        private readonly Action _whenTakenBack;
        private readonly object? _window;
        /// <summary>This window's previous pass handed the quit on to this one.</summary>
        private readonly bool _handedThisQuit;
        private bool _ended;

        /// <summary>How the pass ends, so far.</summary>
        public Ending Ending { get; private set; } = Ending.TakenBack;

        // MARK: - Initializer

        internal Pass(QuitGoingAhead quit, Action whenTakenBack, object? window, bool handedThisQuit)
        {
            _quit = quit;
            _whenTakenBack = whenTakenBack;
            _window = window;
            _handedThisQuit = handedThisQuit;
        }

        // MARK: - Functions

        /// <summary>Past the question: the quit goes ahead, and every repair's Preview Again is abandoned.</summary>
        public void GoAhead()
        {
            _quit.HasGoneAhead = true;
            _quit._presses.AbandonEvery();
        }

        public void TheCloseGoesThrough() => Ending = Ending.GoesThrough;

        public void HandOnToTheNextPass()
        {
            Ending = Ending.HandedOn;
            _quit._handedOnBy = _window;
        }

        /// <summary>
        /// This close is not the quit. A pass handed the quit by this window's
        /// own earlier pass is the one that decides it, so finding the close no
        /// longer quits (a window opened before it ran) TAKES THE QUIT BACK
        /// (the review's L11): the pass that set it has already ended.
        /// </summary>

        public void NotAQuit()
        {
            if (!_handedThisQuit) Ending = Ending.NotAQuit;
        }

        /// <summary>Whatever was said before, the window is still up (the handler failed).</summary>
        public void TakeBack() => Ending = Ending.TakenBack;

        public void Dispose()
        {
            if (_ended) return;
            _ended = true;
            if (Ending != Ending.TakenBack) return;
            _quit.HasGoneAhead = false;
            _whenTakenBack();
        }
    }
}
