local Ffi = require("ffi")

local ChunkUpdate = {}

local CX, CY, CZ = 16, 288, 16
local BufferSize = CX * CY * CZ * 4

pcall(function()
    Ffi.cdef[[
        typedef struct { uint8_t Cr, Cg, Cb, Al; } PackedVoxel;
        typedef struct { uint8_t Roughness, Reflectivity, Refractivity, Wtx; } PackedMaterial;
    ]]
end)

local ScratchVoxelBuffer = nil
local ScratchMaterialBuffer = nil

local function GetIndex(X, Y, Z)
    return Y * (CX * CZ) + Z * CX + X
end

function ChunkUpdate:UpdateChunk(VoxelData, MaterialData)
    -- VoxelData and MaterialData are already FFI arrays, no need for getFFIPointer()
    local VoxelPtr = Ffi.cast("PackedVoxel*", VoxelData)
    local MaterialPtr = Ffi.cast("PackedMaterial*", MaterialData)
    
    if not ScratchVoxelBuffer then
        ScratchVoxelBuffer = Ffi.new("PackedVoxel[?]", CX * CY * CZ)
        ScratchMaterialBuffer = Ffi.new("PackedMaterial[?]", CX * CY * CZ)
    end
    
    Ffi.copy(ScratchVoxelBuffer, VoxelPtr, BufferSize)
    Ffi.copy(ScratchMaterialBuffer, MaterialPtr, BufferSize)
    
    for Py = 0, CY - 1 do
        for Pz = 0, CZ - 1 do
            for Px = 0, CX - 1 do
                local Index = GetIndex(Px, Py, Pz)
                local Vox = ScratchVoxelBuffer[Index]
                local Mat = ScratchMaterialBuffer[Index]
                
                if Mat.Wtx == 1 then
                    if Py > 0 then
                        local BelowIdx = GetIndex(Px, Py - 1, Pz)
                        local BelowVox = ScratchVoxelBuffer[BelowIdx]
                        
                        if BelowVox.Al == 0 then
                            VoxelPtr[BelowIdx].Cr = Vox.Cr
                            VoxelPtr[BelowIdx].Cg = Vox.Cg
                            VoxelPtr[BelowIdx].Cb = Vox.Cb
                            VoxelPtr[BelowIdx].Al = Vox.Al
                            
                            MaterialPtr[BelowIdx].Roughness = Mat.Roughness
                            MaterialPtr[BelowIdx].Reflectivity = Mat.Reflectivity
                            MaterialPtr[BelowIdx].Refractivity = Mat.Refractivity
                            MaterialPtr[BelowIdx].Wtx = Mat.Wtx
                            
                            VoxelPtr[Index].Cr = 0
                            VoxelPtr[Index].Cg = 0
                            VoxelPtr[Index].Cb = 0
                            VoxelPtr[Index].Al = 0
                            
                            MaterialPtr[Index].Roughness = 0
                            MaterialPtr[Index].Reflectivity = 0
                            MaterialPtr[Index].Refractivity = 0
                            MaterialPtr[Index].Wtx = 0
                        else
                            local function Spread(Dx, Dz)
                                local Nx, Nz = Px + Dx, Pz + Dz
                                if Nx >= 0 and Nx < CX and Nz >= 0 and Nz < CZ then
                                    local NIdx = GetIndex(Nx, Py, Nz)
                                    if ScratchVoxelBuffer[NIdx].Al == 0 then
                                        VoxelPtr[NIdx].Cr = Vox.Cr
                                        VoxelPtr[NIdx].Cg = Vox.Cg
                                        VoxelPtr[NIdx].Cb = Vox.Cb
                                        VoxelPtr[NIdx].Al = Vox.Al
                                        
                                        MaterialPtr[NIdx].Roughness = Mat.Roughness
                                        MaterialPtr[NIdx].Reflectivity = Mat.Reflectivity
                                        MaterialPtr[NIdx].Refractivity = Mat.Refractivity
                                        MaterialPtr[NIdx].Wtx = Mat.Wtx
                                    end
                                end
                            end
                            
                            Spread(-1, 0)
                            Spread(1, 0)
                            Spread(0, -1)
                            Spread(0, 1)
                        end
                    end
                end
            end
        end
    end
end

return ChunkUpdate