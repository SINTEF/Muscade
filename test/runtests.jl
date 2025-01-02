module Runtest
    using Test,Literate, DocumenterCitations,Printf,Documenter,Muscade

    @testset "Muscade.jl package" begin
        @testset "TestEspy" begin
            include("TestEspy.jl")
        end
        @testset "TestElementAPI" begin
            include("TestElementAPI.jl")
        end
        @testset "TestAdiff" begin
            include("TestAdiff.jl")
        end
        @testset "TestModelDescription" begin
            include("TestModelDescription.jl")
        end
        @testset "TestAssemble" begin
            include("TestAssemble.jl")
        end
        @testset "TestSweepX2" begin
            include("TestSweepX2.jl")
        end
        @testset "TestSweepX0" begin
            include("TestSweepX0.jl")
        end
        @testset "TestDirectXUA" begin
            include("TestDirectXUA.jl")
        end
        @testset "TestDirectXUA001" begin
            include("TestDirectXUA001.jl")
        end
        @testset "TestScale" begin
            include("TestScale.jl")
        end
        @testset "TestDofConstraints" begin
            include("TestDofConstraints.jl")
        end
        @testset "ElementCost" begin
            include("TestElementCost.jl")
        end
        @testset "BeamElement" begin
            include("TestBeamElement.jl")
        end
        @testset "Rotations" begin
            include("TestRotations.jl")
        end
        @testset "TestUnit" begin
            include("TestUnit.jl")
        end
        @testset "TestBlockSparse" begin
            include("TestBlockSparse.jl")
        end
        @testset "TestFiniteDifferences" begin
            include("TestFiniteDifferences.jl")
        end
        # doctest(Muscade) we do not use doctest, we run Literate.jl on mydemo.jl files that are included in a unit test file
    end
end
