module TestBlockSparse

# cd("C:\\Users\\philippem\\.julia\\dev\\Muscade")
# using Pkg 
# Pkg.activate(".")

using Test,SparseArrays
using Muscade

# Sparse pattern of blocks

nrow = 3
ncol = 2
block        = sparse([1,1,2,3,3],[1,2,2,2,3],randn(5))  # block
pattern      = sparse([1,2,2,3,3],[2,1,2,1,2],[block,block,block,block,block]) # pattern of the blocks in bigsparse
big,bigasm   = prepare(pattern)

zero!(big)
for irow = 1:nrow, icol = 1:ncol
    if irow>1 || icol>1
        addin!(big,block,bigasm,irow,icol)
    end
end

big2 = Matrix(big)
@testset "BlockSparseFromSparse" begin
    @test big2[4:6,1:3] == block
    @test big2[4:6,4:6] == block
end

# Sparse pattern of blocks #2

nrow = 3
ncol = 3
block        = sparse([1,1,1,2,3,4],[1,2,4,2,3,4],ones(6))  # block
pattern      = sparse([1,2,3],[1,2,3],[block,block,block]) # pattern of the blocks in bigsparse
big,bigasm   = prepare(pattern)

@testset "bigasm 2" begin
    @test bigasm.pigr[1] == [1 2 4 5; 0 0 0  0 ; 0  0  0  0 ]
    @test bigasm.pigr[2] == [0 0 0 0; 7 8 10 11; 0  0  0  0 ]
    @test bigasm.pigr[3] == [0 0 0 0; 0 0 0  0 ; 13 14 16 17]
    @test bigasm.pgc == [1,5,9,13]
end

zero!(big)
(i,j,v) = findnz(pattern)
for k = 1:nnz(pattern) 
    addin!(big,block,bigasm,i[k],j[k])
end

big2 = Matrix(big)
@testset "BlockSparseFromSparse 2" begin
    @test big2[1:4,1:4] == block
    @test big2[5:8,5:8] == block
    @test big2[9:12,9:12] == block
end

# Full pattern of blocks

pattern = Matrix{SparseMatrixCSC{𝕣,𝕫}}(undef,nrow,ncol)
for irow = 1:nrow,icol = 1:ncol
    if irow>1 || icol>1
        pattern[irow,icol] = sparse([1,1,2,3,3],[1,2,2,2,3],randn(5))
    end
end
big,bigasm = prepare(pattern)  # uses only the structure of pattern, not the values

zero!(big)
for irow = 1:nrow, icol = 1:ncol
    if irow>1 || icol>1
        block = pattern[irow,icol] # for convenience, in the test, we use the values of pattern as blocks, but that's not typical usage
        addin!(big,block,bigasm,irow,icol) 
    end
end

big2 = Matrix(big)
@testset "BlockSparseFromMatrix" begin
    @test big2[4:6,1:3] == pattern[2,1]
    @test big2[4:6,4:6] == pattern[2,2]
end

end