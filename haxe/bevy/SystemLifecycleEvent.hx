package bevy;

enum SystemLifecycleEvent {
	Started;
	Stopped( reason : SystemStopReason );
}
