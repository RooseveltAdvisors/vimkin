import Testing

@Suite struct HarnessTests {
    @Test func harnessWorks() {
        #expect(1 + 1 == 2)
    }
}
