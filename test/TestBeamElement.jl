module TestEulerBeam3D

using Test, Muscade, StaticArrays

v     = variate{1,3}(SA[.1,.2,.3])
M     = Elements.Rodrigues(v)
w,w∂v = value_∂{1,3}(Elements.Rodrigues⁻¹(M))


a = SA[1,0,0]
b = SA[0,1,1]
r = Elements.adjust(a,b)
R = Elements.Rodrigues(r)
u = R*a
@testset "rotations" begin
    @test v ≈ w
    @test r ≈ [0.0, -1.1107207345395913, 1.1107207345395913]
    @test u ≈ [2.220446049250313e-16, 0.7071067811865476, 0.7071067811865476]
    @test w∂v ≈ [1 0 0;0 1 0;0 0 1]
end



###

model           = Model(:TestModel)
node1           = addnode!(model,𝕣[0,0,0])
node2           = addnode!(model,𝕣[4,3,0])
elnod           = [model.nod[n.inod] for n∈[node1,node2]]
mat             = Elements.BeamCrossSection(EA=10.,EI=3.,GJ=4.)
beam            = Elements.EulerBeam3D(elnod;mat,orient2=SVector(0.,1.,0.))

@testset "constructor" begin
    @test beam.cₘ    ≈ [2.0, 1.5, 0.0]
    @test beam.rₘ    ≈ [0.8 -0.6 0.0; 0.6 0.8 -0.0; 0.0 0.0 1.0]
    @test beam.ζgp   ≈ [-0.2886751345948129, 0.2886751345948129]
    @test beam.ζnod  ≈ [-0.5, 0.5]
    @test beam.tgₘ   ≈ [4.0, 3.0, 0.0]
    @test beam.tgₑ   ≈ [5.0, 0.0, 0.0]
    @test beam.Nε[1] ≈ [-.2, 0, 0, 0, 0, 0, .2, 0, 0, 0, 0, 0]
    @test beam.Nκ[1][2,2] ≈ -0.2078460969082653
    @test beam.Nκ[1][3,5] ≈ 0.2878460969082653
    @test beam.Nu[1][1,1] ≈ 0.2886751345948129
    @test beam.dL    ≈ [2.5, 2.5]
end

t,SP,dbg  = 0.,(;),(status=:testing,)
x = SVector(1.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.)
X = (x,)
U = (SVector{0,𝕣}(),)
A = SVector{0,𝕣}()
R,FB=residual(beam,   X,U,A,t,SP,dbg) 
@testset "residual flex" begin
    @test R        ≈ [1.1323673394544749, 1.0097682842764775, 0.0, 0.0, 0.0, -0.18389858276699608, -1.1323673394544749, -1.0097682842764775, 0.0, 0.0, 0.0, -0.1838985827669961]
    @test FB === nothing
end

###

model           = Model(:TestModel)
node1           = addnode!(model,𝕣[0,0,0])
node2           = addnode!(model,𝕣[1,0,0])
elnod           = [model.nod[n.inod] for n∈[node1,node2]]
mat             = Elements.BeamCrossSection(EA=10.,EI=3.,GJ=4.)
beam            = Elements.EulerBeam3D(elnod;mat,orient2=SVector(0.,1.,0.))
t,SP,dbg  = 0.,(;),(status=:testing,)
x = SVector(0.,0.,0.,1.,0.,0.,0.,0.,0.,0.,0.,0.)
X = (x,)
U = (SVector{0,𝕣}(),)
A = SVector{0,𝕣}()
R,FB=residual(beam,   X,U,A,t,SP,dbg) 
@testset "residual torsion" begin
    @test R        ≈ [0.0, 0.0, 0.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, -4.0, 0.0, 0.0]
    @test FB === nothing
end


end


