import Testing

@Suite(.tags(.unit)) struct HarnessTests {
    @Test func harnessWorks() {
        #expect(1 + 1 == 2)
    }
}
