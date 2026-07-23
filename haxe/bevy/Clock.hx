package bevy;

/** Accumulates time and yields variable or fixed-size simulation ticks. */
class Clock {

	static inline final RELATIVE_EPSILON : Float = 1e-12;

	public var maxTickLength : Float = Math.POSITIVE_INFINITY;
	public var maxTime : Float = Math.POSITIVE_INFINITY;
	public var minTickLength : Float = 1e-16;
	public var paused : Bool = false;
	public var tickCount( default, null ) : Int = 0;
	public var time( default, null ) : Float = 0;
	public var timeScale : Float = 1;

	public function new() {}

	public function addTime( dt : Float ) : Void {

		if ( paused )
			return;

		time += Math.max( 0, dt ) * timeScale;

		if ( time > maxTime )
			time = maxTime;
		tickCount = 0;
	}

	public inline function hasNext() : Bool {

		return
			time >= minTickLength
			|| ( minTickLength < Math.POSITIVE_INFINITY
				&& minTickLength - time <= minTickLength * RELATIVE_EPSILON );
	}

	public function next() : Float {

		final fixed = minTickLength == maxTickLength;
		final tick = //
			if ( fixed && time + minTickLength * RELATIVE_EPSILON >= minTickLength )
				minTickLength
			else
				( time > maxTickLength ? maxTickLength : time );

		time -= tick;
		if ( time < minTickLength * RELATIVE_EPSILON )
			time = 0;
		tickCount++;

		return tick;
	}

	public inline function iterator() : Clock {

		return this;
	}

	public inline function setFixedTickLength( seconds : Float ) : Void {

		if ( seconds <= 0 )
			throw "Fixed tick length must be greater than zero";
		minTickLength = maxTickLength = seconds;
	}

	public inline function setFixedTimestep( seconds : Float ) : Void {

		setFixedTickLength( seconds );
	}

	public inline function setRate( ticksPerSecond : Float ) : Void {

		if ( ticksPerSecond <= 0 )
			throw "Clock rate must be greater than zero";
		setFixedTickLength( 1 / ticksPerSecond );
	}

	public function reset() : Void {

		time = 0;
		tickCount = 0;
	}
}
