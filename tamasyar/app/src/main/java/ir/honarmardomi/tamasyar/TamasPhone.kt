package ir.honarmardomi.tamasyar

/** Local phone helpers: Persian/Arabic digits, contact matching and safe dial input. */
object TamasPhone {
    /** Physical LTR standard telephone layout, independent of Persian UI direction. */
    val KEYPAD_ROWS: List<List<String>> = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf("*", "0", "#")
    )

    fun ascii(input: String): String = buildString(input.length) {
        for (char in input) append(when (char) {
            in '۰'..'۹' -> ('0'.code + (char.code - '۰'.code)).toChar()
            in '٠'..'٩' -> ('0'.code + (char.code - '٠'.code)).toChar()
            else -> char
        })
    }

    fun dial(input: String): String {
        val compact = ascii(input).replace(Regex("[\\s().-]"), "")
        return compact.filterIndexed { i, c ->
            c.isDigit() || c == '*' || c == '#' || (i == 0 && c == '+')
        }.take(40)
    }

    /** Equivalent Iranian mobile numbers map to one shortcut, not duplicated entries. */
    fun normalize(input: String): String {
        val number = dial(input)
        return when {
            number.startsWith("+98") -> "0" + number.drop(3)
            number.startsWith("0098") -> "0" + number.drop(4)
            number.startsWith("98") && number.length == 12 -> "0" + number.drop(2)
            else -> number
        }
    }

    fun initials(name: String): String =
        name.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
            .take(2).map { it.take(1) }.joinToString("").ifBlank { "☎" }
}
