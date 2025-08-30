pub fn append(T: type, a: []T, b: []const T) []u8
{
    var temp = a;
    temp.len = a.len + b.len;

    @memcpy(temp[a.len..temp.len], b);
    return temp;
}

