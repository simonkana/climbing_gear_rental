# Sweep line over half-open intervals (plan §4.3). Pure Ruby, no database.
#
# Returns the maximum number of intervals [start, end) that are active at the
# same instant inside the window [from, to). Intervals are ranges and already
# include any turnaround buffer. Only the window matters: outside it the
# candidate reservation changes nothing.
class CapacityTimeline
  def self.peak(window:, intervals:)
    # 1. Clip every interval to the window and drop the empty ones.
    clipped = intervals.filter_map do |interval|
      start = [ interval.begin, window.begin ].max
      finish = [ interval.end, window.end ].min
      [ start, finish ] if start < finish
    end

    # 2. One +1 event at each start, one -1 event at each end.
    events = clipped.flat_map { |start, finish| [ [ start, +1 ], [ finish, -1 ] ] }

    # 3. Sort by time; at equal times -1 sorts before +1, so touching intervals
    #    do not overlap (half-open, D8).
    # 4. The peak is the highest running sum.
    running = 0
    events.sort.map { |_time, delta| running += delta }.max || 0
  end
end
