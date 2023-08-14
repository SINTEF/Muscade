module TestSparseCat

using Test,SparseArrays
using Muscade

using LinearAlgebra,SparseArrays

nrow = 3
ncol = 2
B = Matrix{SparseMatrixCSC{𝕣,𝕫}}(undef,nrow,ncol)
for irow = 1:nrow
    for icol = 1:ncol
        B[irow,icol] = sparse([1,1,2,3,3],[1,2,2,2,3],randn(5))
    end
end
m0 = hvcat(ncol,(B[i] for i = 1:nrow*ncol)...)
m = cat(B)
m1 = Matrix(m)
m.nzval .= 0
cat!(m,B)
m2 = Matrix(m)

@testset "Turbine gradient" begin
    @test m1 == m2
    @test m1[4:6,1:3] == B[2,1]
end

# using Profile,ProfileView,BenchmarkTools
# nrow = 2
# ncol = 2
# N = 10000
# B = Matrix{SparseMatrixCSC{𝕣,𝕫}}(undef,nrow,ncol)
# for irow = 1:nrow
#     for icol = 1:ncol
#         B[irow,icol] = SparseArrays.sprand(𝕣,N,N,0.1)
#     end
# end
# @btime m0 = hvcat(ncol,(B[i] for i = 1:nrow*ncol)...)
# @btime m = cat(B)
# m = cat(B)
# @btime cat!(m,B)
# Profile.clear()
# Profile.@profile for i=1:10
#     cat!(m,B)
# end
# ProfileView.view(fontsize=30);


end