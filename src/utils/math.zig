pub fn min(first: anytype, second: @TypeOf(first)) @TypeOf(first)
{
    return if (first < second) first else second;
}

pub fn max(first: anytype, second: @TypeOf(first)) @TypeOf(first)
{
    return if (first < second) second else first;
}

